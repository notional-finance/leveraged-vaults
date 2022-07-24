// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Weighted2TokenAuraStrategyContext} from "../BalancerVaultTypes.sol";
import {SettlementHelper} from "../internal/SettlementHelper.sol";

library Weighted2TokenAuraSettlementHelper {
    function settleVaultNormal(
        Weighted2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementState memory state = SettlementHelper._validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementHelper._decodeParamsAndValidate(
            strategyVaultState.lastSettlementTimestamp,
            strategyVaultSettings.settlementCoolDownInMinutes,
            strategyVaultSettings.settlementSlippageLimitPercent,
            data
        );

        _executeNormalSettlement(state, maturity, strategyTokensToRedeem, params);
        strategyVaultState.lastSettlementTimestamp = uint32(block.timestamp);
    }

    function settleVaultPostMaturity(
        Weighted2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        StrategyVaultState memory strategyVaultState = VaultUtils._getStrategyVaultState();
        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
        SettlementState memory state = _validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementHelper._decodeParamsAndValidate(
            strategyVaultState.lastPostMaturitySettlementTimestamp,
            strategyVaultSettings.postMaturitySettlementCoolDownInMinutes,
            strategyVaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );

        _executeNormalSettlement(state, maturity, strategyTokensToRedeem, params);
        strategyVaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
    }

    function settleVaultEmergency(
        Weighted2TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
 /*       (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = _getEmergencySettlementParams(
            VaultUtils._getStrategyVaultSettings(),
            VaultUtils._getStrategyVaultState(),
            maturity
        );

        uint256 redeemStrategyTokenAmount = _convertBPTClaimToStrategyTokens(bptToSettle, maturity);
        int256 expectedUnderlyingRedeemed = convertStrategyToUnderlying(
            address(this),
            redeemStrategyTokenAmount,
            maturity
        );

        SettlementHelper.settleVaultEmergency({
            maturity: maturity,
            bptToSettle: bptToSettle,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            maxUnderlyingSurplus: maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            data: data
        }); */
    }
}
