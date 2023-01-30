// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {
    StrategyContext, 
    TwoTokenPoolContext, 
    StrategyVaultState,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams
} from "../../../common/VaultTypes.sol";
import {Curve2TokenPoolContext, ConvexStakingContext} from "../../CurveVaultTypes.sol";
import {TwoTokenPoolUtils} from "../../../common/internal/pool/TwoTokenPoolUtils.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "../../../common/VaultStorage.sol";
import {ICurve2TokenPool} from "../../../../../interfaces/curve/ICurvePool.sol";

library Curve2TokenPoolUtils {
    using StrategyUtils for StrategyContext;
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TypeConvert for uint256;
    using VaultStorage for StrategyVaultState;

    function _deposit(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ConvexStakingContext memory stakingContext,
        uint256 deposit,
        DepositParams memory params
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 secondaryAmount;
        if (params.tradeData.length != 0) {
            // Allows users to trade on a different DEX instead of Balancer when joining
            (uint256 primarySold, uint256 secondaryBought) = poolContext.basePool._tradePrimaryForSecondary({
                strategyContext: strategyContext,
                data: params.tradeData
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

        poolContext.basePool._mintStrategyTokens(strategyContext, poolClaimMinted);
    }

    function _redeem(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        ConvexStakingContext memory stakingContext,
        uint256 strategyTokens,
        RedeemParams memory params
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = poolContext.basePool._redeemStrategyTokens(strategyContext, strategyTokens);

        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance)
            = _unstakeAndExitPool(poolContext, stakingContext, bptClaim, params);

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
            spotPrice = poolContext.curvePool.get_dy(
                int8(poolContext.basePool.primaryIndex), 
                int8(poolContext.basePool.secondaryIndex), 
                10**poolContext.basePool.primaryDecimals
            );
        } else {
            spotPrice = poolContext.curvePool.get_dy(
                int8(poolContext.basePool.secondaryIndex),
                int8(poolContext.basePool.primaryIndex), 
                10**poolContext.basePool.secondaryDecimals
            );
        }
    }

    /// @notice Gets the time-weighted primary token balance for a given poolClaim Amount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param poolClaim amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function _getTimeWeightedPrimaryBalance(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 poolClaim
    ) internal view returns (uint256 primaryAmount) {
        uint256 oraclePairPrice = poolContext.basePool._getOraclePairPrice(strategyContext);
        
        // tokenIndex == 0 because _getOraclePairPrice always returns the price in terms of
        // the primary currency
        uint256 spotPrice = _getSpotPrice(poolContext, 0);

        primaryAmount = poolContext.basePool._getTimeWeightedPrimaryBalance({
            strategyContext: strategyContext,
            poolClaim: poolClaim,
            oraclePrice: oraclePairPrice,
            spotPrice: spotPrice
        });
    }

    /// @notice We value strategy tokens in terms of the primary balance. The time weighted
    /// primary balance is used in order to prevent pool manipulation.
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return underlyingValue underlying value of strategy tokens
    function _convertStrategyToUnderlying(
        Curve2TokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 strategyTokenAmount
    ) internal view returns (int256 underlyingValue) {
        
        uint256 poolClaim 
            = strategyContext._convertStrategyTokensToPoolClaim(strategyTokenAmount);

        underlyingValue 
            = poolContext._getTimeWeightedPrimaryBalance(strategyContext, poolClaim).toInt();
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

        if (poolContext.basePool.primaryToken == Deployments.ALT_ETH_ADDRESS) {
            msgValue = primaryAmount;
        } else if (poolContext.basePool.secondaryToken == Deployments.ALT_ETH_ADDRESS) {
            msgValue = secondaryAmount;
        }

        poolClaimMinted = ICurve2TokenPool(address(poolContext.curvePool)).add_liquidity{value: msgValue}(
            amounts, minPoolClaim
        );

        bool success = stakingContext.booster.deposit(stakingContext.poolId, poolClaimMinted, true); // stake = true
        require(success);    
    }

    function _unstakeAndExitPool(
        Curve2TokenPoolContext memory poolContext,
        ConvexStakingContext memory stakingContext,
        uint256 poolClaim,
        RedeemParams memory params
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        bool success = stakingContext.rewardPool.withdrawAndUnwrap(poolClaim, false); // claimRewards = false
        if (!success) revert Errors.UnstakeFailed();

        if (params.redeemSingleSided) {
            primaryBalance = ICurve2TokenPool(address(poolContext.curvePool)).remove_liquidity_one_coin(
                poolClaim, int8(poolContext.basePool.primaryIndex), params.minPrimary
            );
        } else {
            uint256[2] memory minAmounts;
            minAmounts[poolContext.basePool.primaryIndex] = params.minPrimary;
            minAmounts[poolContext.basePool.secondaryIndex] = params.minSecondary;
            uint256[2] memory exitBalances = ICurve2TokenPool(address(poolContext.curvePool)).remove_liquidity(
                poolClaim, minAmounts
            );

            (primaryBalance, secondaryBalance) 
                = (exitBalances[poolContext.basePool.primaryIndex], exitBalances[poolContext.basePool.secondaryIndex]);
        }
    }
}