// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Weighted2TokenAuraStrategyContext,
    TwoTokenAuraSettlementContext, 
    WeightedOracleContext,
    StrategyContext,
    SettlementState,
    RedeemParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {TwoTokenAuraSettlementUtils} from "../internal/settlement/TwoTokenAuraSettlementUtils.sol";
import {SettlementUtils} from "../internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";
import {SecondaryBorrowUtils} from "../internal/SecondaryBorrowUtils.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/strategy/TwoTokenAuraStrategyUtils.sol";
import {Weighted2TokenOracleMath} from "../internal/math/Weighted2TokenOracleMath.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";

library Weighted2TokenAuraSettlementHelper {
    using Weighted2TokenOracleMath for WeightedOracleContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    function settleVaultNormal(
        Weighted2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementState memory state = SettlementUtils._getSettlementState(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastSettlementTimestamp,
            context.baseStrategy.vaultSettings.settlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.settlementSlippageLimitPercent,
            data
        );

        context.oracleContext._validateMinExitAmounts({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            minPrimary: params.minPrimary,
            minSecondary: params.minSecondary
        });

        TwoTokenAuraSettlementUtils._executeNormalSettlement({
            context: TwoTokenAuraSettlementContext({
                strategyContext: context.baseStrategy,
                oracleContext: context.oracleContext.baseOracle,
                poolContext: context.poolContext,
                stakingContext: context.stakingContext
            }),
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            params: params
        });

        context.baseStrategy.vaultState.lastSettlementTimestamp = uint32(block.timestamp);
        context.baseStrategy.vaultState._setStrategyVaultState();
    }

    function settleVaultPostMaturity(
        Weighted2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementState memory state = SettlementUtils._getSettlementState(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp,
            context.baseStrategy.vaultSettings.postMaturitySettlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );

        context.oracleContext._validateMinExitAmounts({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            minPrimary: params.minPrimary,
            minSecondary: params.minSecondary
        });

        TwoTokenAuraSettlementUtils._executeNormalSettlement({
            context: TwoTokenAuraSettlementContext({
                strategyContext: context.baseStrategy,
                oracleContext: context.oracleContext.baseOracle,
                poolContext: context.poolContext,
                stakingContext: context.stakingContext
            }),
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            params: params
        });

        context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
        context.baseStrategy.vaultState._setStrategyVaultState();  
    }

    function settleVaultEmergency(
        Weighted2TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = 
            context.baseStrategy._getEmergencySettlementParams(
                context.poolContext.basePool, maturity
            );

        uint256 redeemStrategyTokenAmount = 
            context.baseStrategy._convertBPTClaimToStrategyTokens(bptToSettle);

        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            account: address(this),
            maturity: maturity,
            strategyTokenAmount: redeemStrategyTokenAmount
        });

        SettlementUtils._executeEmergencySettlement({
            maturity: maturity,
            bptToSettle: bptToSettle,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            maxUnderlyingSurplus: maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            data: data
        });       
    }
}
