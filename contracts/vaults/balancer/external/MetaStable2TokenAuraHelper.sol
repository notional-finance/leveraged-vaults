// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    StableOracleContext,
    StrategyContext,
    TwoTokenPoolContext,
    RedeemParams,
    ReinvestRewardParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {BalancerEvents} from "../BalancerEvents.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {SettlementUtils} from "../internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/strategy/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenAuraRewardUtils} from "../internal/reward/TwoTokenAuraRewardUtils.sol";
import {Stable2TokenOracleMath} from "../internal/math/Stable2TokenOracleMath.sol";
import {BalancerVaultStorage} from "../internal/BalancerVaultStorage.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library MetaStable2TokenAuraHelper {
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenAuraRewardUtils for TwoTokenPoolContext;
    using Stable2TokenOracleMath for StableOracleContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using BalancerVaultStorage for StrategyVaultSettings;
    using BalancerVaultStorage for StrategyVaultState;

    function settleVaultNormal(
        MetaStable2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastSettlementTimestamp,
            context.baseStrategy.vaultSettings.settlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.settlementSlippageLimitPercent,
            data
        );

        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        // This check is only necessary during settlement
        context.oracleContext._validatePairPrice({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            primaryAmount: params.minPrimary,
            secondaryAmount: params.minSecondary
        });
        
        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            strategyTokenAmount: strategyTokensToRedeem
        });

        context.baseStrategy._executeSettlement({
            maturity: maturity,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            redeemStrategyTokenAmount: strategyTokensToRedeem,
            params: params
        });

        context.baseStrategy.vaultState.lastSettlementTimestamp = uint32(block.timestamp);
        context.baseStrategy.vaultState.setStrategyVaultState();

        emit BalancerEvents.VaultSettlement(maturity, strategyTokensToRedeem);
    }

    function settleVaultPostMaturity(
        MetaStable2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp,
            context.baseStrategy.vaultSettings.postMaturitySettlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );

        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        // This check is only necessary during settlement
        context.oracleContext._validatePairPrice({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            primaryAmount: params.minPrimary,
            secondaryAmount: params.minSecondary
        });

        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            strategyTokenAmount: strategyTokensToRedeem
        });

        context.baseStrategy._executeSettlement({
            maturity: maturity,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            redeemStrategyTokenAmount: strategyTokensToRedeem,
            params: params
        });

        context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
        context.baseStrategy.vaultState.setStrategyVaultState();  

        emit BalancerEvents.VaultSettlement(maturity, strategyTokensToRedeem);
    }

    function settleVaultEmergency(
        MetaStable2TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        // This check is only necessary during settlement
        context.oracleContext._validatePairPrice({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            primaryAmount: params.minPrimary,
            secondaryAmount: params.minSecondary
        });

        (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = 
            context.baseStrategy._getEmergencySettlementParams({
                poolContext: context.poolContext.basePool, 
                maturity: maturity, 
                totalBPTSupply: IERC20(context.poolContext.basePool.pool).totalSupply()
            });

        uint256 redeemStrategyTokenAmount = 
            context.baseStrategy._convertBPTClaimToStrategyTokens(bptToSettle);

        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            strategyTokenAmount: redeemStrategyTokenAmount
        });

        context.baseStrategy._executeSettlement({
            maturity: maturity,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            params: params
        });

        emit BalancerEvents.EmergencyVaultSettlement(maturity, bptToSettle, redeemStrategyTokenAmount);
    }

    function reinvestReward(
        MetaStable2TokenAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external {
        StrategyContext calldata strategyContext = context.baseStrategy;
        TwoTokenPoolContext calldata poolContext = context.poolContext; 
        StableOracleContext calldata oracleContext = context.oracleContext;

        (
            address rewardToken, 
            uint256 primaryAmount, 
            uint256 secondaryAmount
        ) = poolContext._executeRewardTrades(
            context.stakingContext,
            strategyContext.tradingModule,
            params.tradeData,
            strategyContext.vaultSettings.maxRewardTradeSlippageLimitPercent
        );

        // Make sure we are joining with the right proportion to minimize slippage
        oracleContext._validateSpotPriceAndPairPrice({
            poolContext: poolContext,
            tradingModule: strategyContext.tradingModule,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });

        uint256 bptAmount = strategyContext._joinPoolAndStake({
            stakingContext: context.stakingContext,
            poolContext: poolContext,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount,
            /// @notice minBPT is not required to be set by the caller because primaryAmount
            /// and secondaryAmount are already validated
            minBPT: params.minBPT        
        });

        emit BalancerEvents.RewardReinvested(rewardToken, primaryAmount, secondaryAmount, bptAmount); 
    }
}
