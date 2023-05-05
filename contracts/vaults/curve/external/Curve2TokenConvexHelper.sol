// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    Curve2TokenConvexStrategyContext,
    Curve2TokenPoolContext
} from "../CurveVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    TwoTokenPoolContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams
} from "../../common/VaultTypes.sol";
import {TwoTokenPoolUtils} from "../../common/internal/pool/TwoTokenPoolUtils.sol";
import {SettlementUtils} from "../../common/internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../../common/internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {Curve2TokenPoolUtils} from "../internal/pool/Curve2TokenPoolUtils.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library Curve2TokenConvexHelper {
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultStorage for StrategyVaultState;

    function deposit(
        Curve2TokenConvexStrategyContext memory context,
        uint256 deposit,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        strategyTokensMinted = context.poolContext._deposit({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            deposit: deposit,
            params: params
        });
    }

    function redeem(
        Curve2TokenConvexStrategyContext memory context,
        uint256 strategyTokens,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            strategyTokens: strategyTokens,
            params: params
        });
    }

    function settleVault(
        Curve2TokenConvexStrategyContext calldata context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) external {
        uint256 poolClaimToSettle = context.baseStrategy._convertStrategyTokensToPoolClaim(strategyTokensToRedeem);
        
        _executeSettlement({
            strategyContext: context.baseStrategy,
            poolContext: context.poolContext,
            maturity: maturity,
            poolClaimToSettle: poolClaimToSettle,
            redeemStrategyTokenAmount: strategyTokensToRedeem,
            params: params
        });

        emit VaultEvents.VaultSettlement(maturity, poolClaimToSettle, strategyTokensToRedeem);
    }

    function settleVaultEmergency(
        Curve2TokenConvexStrategyContext calldata context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );

        uint256 poolClaimToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.poolContext.basePool.poolToken.totalSupply()
        });

        uint256 redeemStrategyTokenAmount = 
            context.baseStrategy._convertPoolClaimToStrategyTokens(poolClaimToSettle);

        _executeSettlement({
            strategyContext: context.baseStrategy,
            poolContext: context.poolContext,
            maturity: maturity,
            poolClaimToSettle: poolClaimToSettle,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            params: params
        });

        emit VaultEvents.EmergencyVaultSettlement(maturity, poolClaimToSettle, redeemStrategyTokenAmount);    
    }

    function _executeSettlement(
        StrategyContext calldata strategyContext,
        Curve2TokenPoolContext calldata poolContext,
        uint256 maturity,
        uint256 poolClaimToSettle,
        uint256 redeemStrategyTokenAmount,
        RedeemParams memory params
    ) private {
        (uint256 spotPrice, uint256 oraclePrice) = poolContext._getSpotPriceAndOraclePrice(strategyContext);

        /// @notice params.minPrimary and params.minSecondary are not required to be passed in by the caller
        /// for this strategy vault
        (params.minPrimary, params.minSecondary) = poolContext.basePool._getMinExitAmounts({
            strategyContext: strategyContext,
            oraclePrice: oraclePrice,
            spotPrice: spotPrice,
            poolClaim: poolClaimToSettle
        });

        int256 expectedUnderlyingRedeemed = poolContext._convertStrategyToUnderlying({
            strategyContext: strategyContext,
            strategyTokenAmount: redeemStrategyTokenAmount,
            oraclePrice: oraclePrice,
            spotPrice: spotPrice
        });

        strategyContext._executeSettlement({
            maturity: maturity,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            params: params
        });    
    }

    function reinvestReward(
        Curve2TokenConvexStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external {
        StrategyContext memory strategyContext = context.baseStrategy;
        Curve2TokenPoolContext calldata poolContext = context.poolContext; 

        (
            address rewardToken, 
            uint256 primaryAmount, 
            uint256 secondaryAmount
        ) = poolContext.basePool._executeRewardTrades({
            rewardTokens: context.stakingContext.rewardTokens,
            tradingModule: strategyContext.tradingModule,
            data: params.tradeData
        });

        // Make sure we are joining with the right proportion to minimize slippage
        poolContext._validateSpotPriceAndPairPrice({
            strategyContext: strategyContext,
            oraclePrice: poolContext.basePool._getOraclePairPrice(strategyContext),
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });

        uint256 poolClaimAmount = poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: context.stakingContext,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount,
            /// @notice minPoolClaim is not required to be set by the caller because primaryAmount
            /// and secondaryAmount are already validated
            minPoolClaim: params.minPoolClaim      
        });

        strategyContext.vaultState.totalPoolClaim += poolClaimAmount;
        strategyContext.vaultState.setStrategyVaultState(); 

        emit VaultEvents.RewardReinvested(rewardToken, primaryAmount, secondaryAmount, poolClaimAmount);
    }
}
