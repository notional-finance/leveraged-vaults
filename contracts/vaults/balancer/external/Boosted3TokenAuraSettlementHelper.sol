// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext, 
    StrategyContext,
    SettlementState,
    RedeemParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {Boosted3TokenAuraSettlementUtils} from "../internal/settlement/Boosted3TokenAuraSettlementUtils.sol";
import {SettlementUtils} from "../internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";
import {Boosted3TokenAuraStrategyUtils} from "../internal/strategy/Boosted3TokenAuraStrategyUtils.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";

library Boosted3TokenAuraSettlementHelper {
    using Boosted3TokenAuraSettlementUtils for Boosted3TokenAuraStrategyContext;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    function settleVaultNormal(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementState memory state = SettlementUtils._getSettlementState(maturity, strategyTokensToRedeem);
        SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastSettlementTimestamp,
            context.baseStrategy.vaultSettings.settlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.settlementSlippageLimitPercent,
            data
        );

        context._executeNormalSettlement({
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem
        });

        context.baseStrategy.vaultState.lastSettlementTimestamp = uint32(block.timestamp);
        context.baseStrategy.vaultState._setStrategyVaultState();
    }

    function settleVaultPostMaturity(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementState memory state = SettlementUtils._getSettlementState(maturity, strategyTokensToRedeem);
        SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp,
            context.baseStrategy.vaultSettings.postMaturitySettlementCoolDownInMinutes,
            context.baseStrategy.vaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );

        context._executeNormalSettlement({
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem
        });

        context.baseStrategy.vaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
        context.baseStrategy.vaultState._setStrategyVaultState();  
    }

    function settleVaultEmergency(
        Boosted3TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = 
            context.baseStrategy._getEmergencySettlementParams(
                context.poolContext.basePool.basePool, maturity
            );

        uint256 redeemStrategyTokenAmount = context.baseStrategy._convertBPTClaimToStrategyTokens(
            bptToSettle, NotionalUtils._totalSupplyInMaturity(maturity)
        );

        int256 expectedUnderlyingRedeemed = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            strategyTokenAmount: redeemStrategyTokenAmount,
            maturity: maturity
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
