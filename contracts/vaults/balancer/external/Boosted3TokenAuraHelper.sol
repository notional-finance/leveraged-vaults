// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext, 
    StrategyContext,
    RedeemParams,
    ReinvestRewardParams,
    ThreeTokenPoolContext,
    StrategyContext,
    AuraStakingContext,
    BoostedOracleContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {BalancerEvents} from "../BalancerEvents.sol";
import {SettlementUtils} from "../internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";
import {Boosted3TokenPoolUtils} from "../internal/pool/Boosted3TokenPoolUtils.sol";
import {Boosted3TokenAuraRewardUtils} from "../internal/reward/Boosted3TokenAuraRewardUtils.sol";
import {BalancerVaultStorage} from "../internal/BalancerVaultStorage.sol";
import {StableMath} from "../internal/math/StableMath.sol";

library Boosted3TokenAuraHelper {
    using Boosted3TokenAuraRewardUtils for ThreeTokenPoolContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using BalancerVaultStorage for StrategyVaultSettings;

    function settleVault(
        Boosted3TokenAuraStrategyContext calldata context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) external {
        uint256 bptToSettle = context.baseStrategy._convertStrategyTokensToBPTClaim(strategyTokensToRedeem);

        // Calculate minPrimary using Chainlink oracle data
        params.minPrimary = context.poolContext._getTimeWeightedPrimaryBalance(
            context.oracleContext, context.baseStrategy.tradingModule, bptToSettle
        );
        params.minPrimary = params.minPrimary * BalancerConstants.MAX_BOOSTED_POOL_SLIPPAGE_PERCENT / 
            uint256(BalancerConstants.VAULT_PERCENT_BASIS);

        int256 expectedUnderlyingRedeemed = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
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
        Boosted3TokenAuraStrategyContext calldata context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            poolContext: context.poolContext.basePool.basePool, 
            maturity: maturity, 
            totalBPTSupply: context.poolContext._getVirtualSupply(context.oracleContext)
        });

        // Calculate minPrimary using Chainlink oracle data
        params.minPrimary = context.poolContext._getTimeWeightedPrimaryBalance(
            context.oracleContext, context.baseStrategy.tradingModule, bptToSettle
        );
        params.minPrimary = params.minPrimary * BalancerConstants.MAX_BOOSTED_POOL_SLIPPAGE_PERCENT / 
            uint256(BalancerConstants.VAULT_PERCENT_BASIS);

        uint256 redeemStrategyTokenAmount 
            = context.baseStrategy._convertBPTClaimToStrategyTokens(bptToSettle);

        // @audit reduce code duplication here
        int256 expectedUnderlyingRedeemed = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            strategyTokenAmount: redeemStrategyTokenAmount
        });

        context.baseStrategy._executeSettlement({
            maturity: maturity,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            params: params
        });

        // @audit why not emit inside executeSettlement?
        emit BalancerEvents.EmergencyVaultSettlement(maturity, bptToSettle, redeemStrategyTokenAmount);
    }

    function reinvestReward(
        Boosted3TokenAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external {        
        StrategyContext calldata strategyContext = context.baseStrategy;
        BoostedOracleContext calldata oracleContext = context.oracleContext;
        AuraStakingContext calldata stakingContext = context.stakingContext;

        (address rewardToken, uint256 primaryAmount) = context.poolContext._executeRewardTrades({
            stakingContext: stakingContext,
            tradingModule: strategyContext.tradingModule,
            data: params.tradeData,
            slippageLimit: strategyContext.vaultSettings.maxRewardTradeSlippageLimitPercent
        });

        uint256 minBPT = context.poolContext._getMinBPT(
            oracleContext, strategyContext.tradingModule, primaryAmount
        );
        uint256 bptAmount = context.poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: stakingContext,
            deposit: primaryAmount,
            minBPT: minBPT
        });

        emit BalancerEvents.RewardReinvested(rewardToken, primaryAmount, 0, bptAmount); 
    }
}
