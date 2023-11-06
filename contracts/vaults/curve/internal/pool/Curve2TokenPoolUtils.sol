// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {
    StrategyContext, 
    TwoTokenPoolContext,
    StrategyVaultSettings,
    StrategyVaultState,
    DepositParams,
    RedeemParams
} from "../../../common/VaultTypes.sol";
import {CurveConstants} from "../CurveConstants.sol";
import {Curve2TokenPoolContext, ConvexStakingContext} from "../../CurveVaultTypes.sol";
import {TwoTokenPoolUtils} from "../../../common/internal/pool/TwoTokenPoolUtils.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "../../../common/VaultStorage.sol";
import {VaultConstants} from "../../../common/VaultConstants.sol";
import {
    ICurvePool,
    ICurve2TokenPool, 
    ICurve2TokenPoolV1, 
    ICurve2TokenPoolV2
} from "../../../../../interfaces/curve/ICurvePool.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "../../../../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "../../../../../interfaces/convex/IConvexRewardPool.sol";
import {
    ReinvestRewardParams
} from "../../../../../interfaces/notional/ISingleSidedLPStrategyVault.sol";

library Curve2TokenPoolUtils {
    using StrategyUtils for StrategyContext;
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TypeConvert for uint256;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;

    function _deposit(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ConvexStakingContext memory stakingContext,
        uint256 deposit,
        DepositParams memory params
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 secondaryAmount;
        if (params.depositTrades.length > 0) {
            require(params.depositTrades.length == 1);
            // Allows users to trade on a different DEX when joining
            (uint256 primarySold, uint256 secondaryBought) = poolContext.basePool._tradePrimaryForSecondary({
                strategyContext: strategyContext,
                params: params.depositTrades[0]
            });
            deposit -= primarySold;
            secondaryAmount = secondaryBought;
        }

        uint256 poolClaimMinted = poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: stakingContext,
            primaryAmount: deposit,
            secondaryAmount: secondaryAmount,
            minPoolClaim: params.minPoolClaim
        });

        strategyTokensMinted = strategyContext._mintStrategyTokens(poolClaimMinted);
    }

    function _redeem(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ConvexStakingContext memory stakingContext,
        uint256 strategyTokens,
        RedeemParams memory params
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 poolClaim = strategyContext._redeemStrategyTokens(strategyTokens);

        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance)
            = _unstakeAndExitPool(poolContext, stakingContext, poolClaim, params);

        finalPrimaryBalance = primaryBalance;
        if (secondaryBalance > 0) {
            uint256 primaryPurchased = poolContext.basePool._sellSecondaryBalance(
                strategyContext, params, secondaryBalance
            );

            finalPrimaryBalance += primaryPurchased;
        }
    }

    function _getSpotPrice(
        Curve2TokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        require(tokenIndex < 2);
        if (tokenIndex == 0) {
            spotPrice = ICurvePool(poolContext.curvePool).get_dy(
                int8(poolContext.basePool.primaryIndex), 
                int8(poolContext.basePool.secondaryIndex), 
                10**poolContext.basePool.primaryDecimals // 1 unit of primary
            );
            uint256 secondaryPrecision = 10**poolContext.basePool.secondaryDecimals;
            spotPrice = spotPrice * CurveConstants.CURVE_PRECISION / secondaryPrecision;
        } else {
            spotPrice = ICurvePool(poolContext.curvePool).get_dy(
                int8(poolContext.basePool.secondaryIndex),
                int8(poolContext.basePool.primaryIndex), 
                10**poolContext.basePool.secondaryDecimals // 1 unit of secondary
            );
            uint256 primaryPrecision = 10**poolContext.basePool.primaryDecimals;
            spotPrice = spotPrice * CurveConstants.CURVE_PRECISION / primaryPrecision;
        }
    }

    function _validateSpotPriceAndPairPrice(
        Curve2TokenPoolContext calldata poolContext,
        StrategyContext memory strategyContext,
        uint256 oraclePrice,
        uint256 primaryAmount,
        uint256 secondaryAmount
    ) internal view {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        uint256 spotPrice = _getSpotPrice({
            poolContext: poolContext,
            tokenIndex: 0
        });

        /// @notice Check spotPrice against oracle price to make sure that 
        /// the pool is not being manipulated
        strategyContext._checkPriceLimit(oraclePrice, spotPrice);

        /**
        TODO: below here nothing is returned, the reward reinvestment is the only place this is used
        uint256 primaryPrecision = 10**poolContext.basePool.primaryDecimals;
        uint256 secondaryPrecision = 10**poolContext.basePool.secondaryDecimals;

        // Convert input amounts and pool amounts to CURVE_PRECISION (1e18)
        primaryAmount = primaryAmount * strategyContext.poolClaimPrecision / primaryPrecision;
        secondaryAmount = secondaryAmount * strategyContext.poolClaimPrecision / secondaryPrecision;

        uint256 primaryPoolBalance = poolContext.basePool.primaryBalance * CurveConstants.CURVE_PRECISION 
            / primaryPrecision;
        uint256 secondaryPoolBalance = poolContext.basePool.secondaryBalance * CurveConstants.CURVE_PRECISION 
            / secondaryPrecision;
        */
    }
    
    /// @notice We value strategy tokens in terms of the primary balance. The time weighted
    /// primary balance is used in order to prevent pool manipulation.
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param vaultShareAmount amount of vault shares
    /// @return underlyingValue underlying value of strategy tokens
    function _convertStrategyToUnderlying(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 vaultShareAmount
    ) internal view returns (int256 underlyingValue) {
        
        uint256 poolClaim 
            = strategyContext._convertStrategyTokensToPoolClaim(vaultShareAmount);

        (uint256 spotPrice, uint256 oraclePrice) = _getSpotPriceAndOraclePrice(poolContext, strategyContext);

        underlyingValue 
            = poolContext.basePool._getTimeWeightedPrimaryBalance({
                strategyContext: strategyContext,
                poolClaim: poolClaim,
                oraclePrice: oraclePrice, 
                spotPrice: spotPrice
            }).toInt();
    }   

    function _joinPoolAndStake(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ConvexStakingContext memory stakingContext,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 minPoolClaim
    ) internal returns (uint256 poolClaimMinted) {
        uint256[2] memory amounts;
        uint256 msgValue;
        amounts[poolContext.basePool.primaryIndex] = primaryAmount;
        amounts[poolContext.basePool.secondaryIndex] = secondaryAmount;

        if (poolContext.basePool.primaryToken == Deployments.ETH_ADDRESS) {
            msgValue = primaryAmount;
        } else if (poolContext.basePool.secondaryToken == Deployments.ETH_ADDRESS) {
            msgValue = secondaryAmount;
        }

        if (poolContext.isV2) {
            poolClaimMinted = ICurve2TokenPoolV2(address(poolContext.curvePool)).add_liquidity{value: msgValue}(
                amounts, minPoolClaim, 0 < msgValue // use_eth = true if msgValue > 0
            );
        } else {
            poolClaimMinted = ICurve2TokenPoolV1(address(poolContext.curvePool)).add_liquidity{value: msgValue}(
                amounts, minPoolClaim
            );
        }

        bool success;
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            success = IConvexBooster(stakingContext.booster).deposit(
                stakingContext.poolId, poolClaimMinted, true
            ); // stake = true
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            success = IConvexBoosterArbitrum(stakingContext.booster).deposit(
                stakingContext.poolId, poolClaimMinted
            );
        }
        require(success);
    }

    function _unstakeAndExitPool(
        Curve2TokenPoolContext memory poolContext,
        ConvexStakingContext memory stakingContext,
        uint256 poolClaim,
        RedeemParams memory params
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        // Withdraw pool tokens back to the vault for redemption
        bool success;
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            success = IConvexRewardPool(stakingContext.rewardPool).withdrawAndUnwrap(
                poolClaim, false
            ); // claimRewards = false
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            success = IConvexRewardPoolArbitrum(stakingContext.rewardPool).withdraw(
                poolClaim, false
            ); // claimRewards = false
        }
        
        if (!success) revert Errors.UnstakeFailed();

        uint8 primaryIndex = poolContext.basePool.primaryIndex;
        uint8 secondaryIndex = poolContext.basePool.secondaryIndex;
        ICurve2TokenPool pool = ICurve2TokenPool(address(poolContext.curvePool));
        if (params.redemptionTrades.length == 0) {
            // Redeem single-sided
            primaryBalance = pool.remove_liquidity_one_coin(
                poolClaim, int8(primaryIndex), params.minAmounts[primaryIndex]
            );
        } else {
            // Redeem proportionally
            uint256[2] memory minAmounts;
            minAmounts[primaryIndex] = params.minAmounts[primaryIndex];
            minAmounts[secondaryIndex] = params.minAmounts[secondaryIndex];
            uint256[2] memory exitBalances = pool.remove_liquidity(poolClaim, minAmounts);

            (primaryBalance, secondaryBalance) = (
                exitBalances[poolContext.basePool.primaryIndex],
                exitBalances[poolContext.basePool.secondaryIndex]
            );
        }
    }

    function _getSpotPriceAndOraclePrice(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext
    ) internal view returns (uint256 spotPrice, uint256 oraclePrice) {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        // Validate the spot price to make sure the pool is not being manipulated
        spotPrice = poolContext._getSpotPrice(0); // tokenIndex
        oraclePrice = poolContext.basePool._getOraclePairPrice(strategyContext);
    }
}