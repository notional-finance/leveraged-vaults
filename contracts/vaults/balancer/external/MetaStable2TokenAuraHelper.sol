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
import {SettlementUtils} from "../internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";
import {TwoTokenPoolUtils} from "../internal/pool/TwoTokenPoolUtils.sol";
import {TwoTokenAuraRewardUtils} from "../internal/reward/TwoTokenAuraRewardUtils.sol";
import {Stable2TokenOracleMath} from "../internal/math/Stable2TokenOracleMath.sol";
import {BalancerVaultStorage} from "../internal/BalancerVaultStorage.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library MetaStable2TokenAuraHelper {
    using TwoTokenAuraRewardUtils for TwoTokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using Stable2TokenOracleMath for StableOracleContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using BalancerVaultStorage for StrategyVaultSettings;

    function settleVault(
        MetaStable2TokenAuraStrategyContext calldata context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) external {
        uint256 bptToSettle = context.baseStrategy._convertStrategyTokensToBPTClaim(strategyTokensToRedeem);

        /// @notice params.minPrimary and params.minSecondary are not required for this strategy vault
        (params.minPrimary, params.minSecondary) = context.oracleContext._getMinExitAmounts({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            bptAmount: bptToSettle
        });
        
        int256 expectedUnderlyingRedeemed = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext.baseOracle,
            strategyTokenAmount: strategyTokensToRedeem
        });

        context.baseStrategy._executeSettlement({
            maturity: maturity,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            redeemStrategyTokenAmount: strategyTokensToRedeem,
            params: params
        });

        emit BalancerEvents.VaultSettlement(maturity, strategyTokensToRedeem);
    }

    function settleVaultEmergency(
        MetaStable2TokenAuraStrategyContext calldata context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            poolContext: context.poolContext.basePool, 
            maturity: maturity, 
            totalBPTSupply: IERC20(context.poolContext.basePool.pool).totalSupply()
        });

        (params.minPrimary, params.minSecondary) = context.oracleContext._getMinExitAmounts({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            bptAmount: bptToSettle
        });

        uint256 redeemStrategyTokenAmount = 
            context.baseStrategy._convertBPTClaimToStrategyTokens(bptToSettle);

        int256 expectedUnderlyingRedeemed = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext.baseOracle,
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

        uint256 bptAmount = poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: context.stakingContext,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount,
            /// @notice minBPT is not required to be set by the caller because primaryAmount
            /// and secondaryAmount are already validated
            minBPT: params.minBPT        
        });

        emit BalancerEvents.RewardReinvested(rewardToken, primaryAmount, secondaryAmount, bptAmount); 
    }
}
