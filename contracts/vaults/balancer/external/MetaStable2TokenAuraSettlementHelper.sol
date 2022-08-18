// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    TwoTokenAuraSettlementContext, 
    StableOracleContext,
    StrategyContext,
    RedeemParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {Events} from "../../../global/Events.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {SettlementUtils} from "../internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/strategy/TwoTokenAuraStrategyUtils.sol";
import {Stable2TokenOracleMath} from "../internal/math/Stable2TokenOracleMath.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";

library MetaStable2TokenAuraSettlementHelper {
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Stable2TokenOracleMath for StableOracleContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

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
        context.baseStrategy.vaultState._setStrategyVaultState();

        emit Events.VaultSettlement(maturity, strategyTokensToRedeem);
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
        context.baseStrategy.vaultState._setStrategyVaultState();  

        emit Events.VaultSettlement(maturity, strategyTokensToRedeem);
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
            context.baseStrategy._getEmergencySettlementParams(
                context.poolContext.basePool, maturity
            );

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

        emit Events.EmergencyVaultSettlement(maturity, bptToSettle, redeemStrategyTokenAmount);
    }
}
