// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext, 
    StrategyContext,
    RedeemParams,
    ThreeTokenPoolContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {BalancerEvents} from "../BalancerEvents.sol";
import {SettlementUtils} from "../internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";
import {Boosted3TokenPoolUtils} from "../internal/pool/Boosted3TokenPoolUtils.sol";
import {Boosted3TokenAuraStrategyUtils} from "../internal/strategy/Boosted3TokenAuraStrategyUtils.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";

library Boosted3TokenAuraSettlementHelper {
    using Boosted3TokenAuraStrategyUtils for StrategyContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    // @audit switch to calldata
    function settleVaultNormal(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        // @audit is there anything different about this method versus settleVaultPostMaturity?
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastSettlementTimestamp,
            context.baseStrategy.vaultSettings.settlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.settlementSlippageLimitPercent,
            data
        );

        uint256 bptToSettle = context.baseStrategy._convertStrategyTokensToBPTClaim(strategyTokensToRedeem);

        // Calculate minPrimary using Chainlink oracle data
        // @audit why not just use a stack variable here instead of updating a memory object?
        params.minPrimary = context.poolContext._getTimeWeightedPrimaryBalance(
            context.oracleContext, context.baseStrategy.tradingModule, bptToSettle
        );
        params.minPrimary = params.minPrimary * BalancerConstants.MAX_BOOSTED_POOL_SLIPPAGE_PERCENT / 
            uint256(BalancerConstants.PERCENTAGE_DECIMALS);

        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
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
        Boosted3TokenAuraStrategyContext memory context,
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

        uint256 bptToSettle = context.baseStrategy._convertStrategyTokensToBPTClaim(strategyTokensToRedeem);

        // Calculate minPrimary using Chainlink oracle data
        params.minPrimary = context.poolContext._getTimeWeightedPrimaryBalance(
            context.oracleContext, context.baseStrategy.tradingModule, bptToSettle
        );
        params.minPrimary = params.minPrimary * BalancerConstants.MAX_BOOSTED_POOL_SLIPPAGE_PERCENT / 
            uint256(BalancerConstants.PERCENTAGE_DECIMALS);

        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
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

        // @audit why not emit inside executeSettlement?
        emit BalancerEvents.VaultSettlement(maturity, strategyTokensToRedeem);
    }

    function settleVaultEmergency(
        Boosted3TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        // @audit maxUnderlyingSurplus is never used?
        (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = 
            context.baseStrategy._getEmergencySettlementParams({
                poolContext: context.poolContext.basePool.basePool, 
                maturity: maturity, 
                totalBPTSupply: context.poolContext._getVirtualSupply(context.oracleContext)
            });

        // Calculate minPrimary using Chainlink oracle data
        // @audit why not just use a stack variable here instead of updating a memory object?
        params.minPrimary = context.poolContext._getTimeWeightedPrimaryBalance(
            context.oracleContext, context.baseStrategy.tradingModule, bptToSettle
        );
        params.minPrimary = params.minPrimary * BalancerConstants.MAX_BOOSTED_POOL_SLIPPAGE_PERCENT / 
            uint256(BalancerConstants.PERCENTAGE_DECIMALS);

        uint256 redeemStrategyTokenAmount 
            = context.baseStrategy._convertBPTClaimToStrategyTokens(bptToSettle);

        // @audit reduce code duplication here
        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
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
}
