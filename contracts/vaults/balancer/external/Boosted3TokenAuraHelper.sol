// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext, 
    StrategyContext,
    DepositParams,
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

    function deposit(
        Boosted3TokenAuraStrategyContext memory context,
        DepositParams memory params,
        uint256 deposit
    ) external returns (uint256 strategyTokensMinted) {
        strategyTokensMinted = context.poolContext._deposit({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            oracleContext: context.oracleContext, 
            deposit: deposit,
            minBPT: params.minBPT
        });
    }

    function redeem(
        Boosted3TokenAuraStrategyContext memory context,
        RedeemParams memory params,
        uint256 strategyTokens
    ) external returns (uint256 finalPrimaryBalance) {
        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            strategyTokens: strategyTokens,
            minPrimary: params.minPrimary
        });
    }

    function settleVault(
        Boosted3TokenAuraStrategyContext calldata context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) external {
        uint256 bptToSettle = context.baseStrategy._convertStrategyTokensToBPTClaim(strategyTokensToRedeem);

        _executeSettlement({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            maturity: maturity,
            bptToSettle: bptToSettle,
            redeemStrategyTokenAmount: strategyTokensToRedeem,
            params: params
        });

        emit BalancerEvents.VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem);
    }

    function settleVaultEmergency(
        Boosted3TokenAuraStrategyContext calldata context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );

        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            poolContext: context.poolContext.basePool.basePool, 
            maturity: maturity, 
            totalBPTSupply: context.poolContext._getVirtualSupply(context.oracleContext)
        });

        uint256 redeemStrategyTokenAmount 
            = context.baseStrategy._convertBPTClaimToStrategyTokens(bptToSettle);
        
        _executeSettlement({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            maturity: maturity,
            bptToSettle: bptToSettle,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            params: params
        });

        emit BalancerEvents.EmergencyVaultSettlement(maturity, bptToSettle, redeemStrategyTokenAmount);
    }

    function _executeSettlement(
        StrategyContext calldata strategyContext,
        BoostedOracleContext calldata oracleContext,
        ThreeTokenPoolContext calldata poolContext,
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeemStrategyTokenAmount,
        RedeemParams memory params
    ) private {
        // Calculate minPrimary using Chainlink oracle data
        params.minPrimary = poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, strategyContext, bptToSettle
        );
        params.minPrimary = params.minPrimary * strategyContext.vaultSettings.balancerPoolSlippageLimitPercent / 
            uint256(BalancerConstants.VAULT_PERCENT_BASIS);

        int256 expectedUnderlyingRedeemed = poolContext._convertStrategyToUnderlying({
            strategyContext: strategyContext,
            oracleContext: oracleContext,
            strategyTokenAmount: redeemStrategyTokenAmount
        });

        strategyContext._executeSettlement({
            maturity: maturity,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            params: params
        });
    }

    function reinvestReward(
        Boosted3TokenAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external {        
        StrategyContext calldata strategyContext = context.baseStrategy;
        BoostedOracleContext calldata oracleContext = context.oracleContext;
        AuraStakingContext calldata stakingContext = context.stakingContext;
        ThreeTokenPoolContext calldata poolContext = context.poolContext;

        (address rewardToken, uint256 primaryAmount) = poolContext._executeRewardTrades({
            stakingContext: stakingContext,
            tradingModule: strategyContext.tradingModule,
            data: params.tradeData,
            slippageLimit: strategyContext.vaultSettings.maxRewardTradeSlippageLimitPercent
        });
        
        /// @notice This function is used to validate the spot price against
        /// the oracle price. The return values are not used.
        poolContext._getValidatedPoolData(oracleContext, strategyContext);

        uint256 bptAmount = context.poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: stakingContext,
            oracleContext: oracleContext,
            deposit: primaryAmount,
            /// @notice Setting minBPT to 0 based on the following assumptions
            /// 1. _getValidatedPoolData already validates the spot price to make sure
            /// the pool isn't being manipulated
            /// 2. We check maxBalancerPoolShare before joining to make sure the pool
            /// has adequate liquidity
            /// 3. Manipulating the pool before calling reinvestReward isn't expected
            /// to be very profitable for the attacker because the function gets called
            /// very frequently (relatively small trades)
            minBPT: 0
        });

        emit BalancerEvents.RewardReinvested(rewardToken, primaryAmount, 0, bptAmount); 
    }
}
