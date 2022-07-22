// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {LibBalancerStorage} from "./LibBalancerStorage.sol";
import {
    StrategyVaultSettings, 
    StrategyVaultState, 
    SettlementState
} from "../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {Constants} from "../../../global/Constants.sol";

library VaultUtils {
    function _getStrategyVaultSettings() internal view returns (StrategyVaultSettings memory) {
        mapping(uint256 => StrategyVaultSettings) storage store = LibBalancerStorage.getStrategyVaultSettings();
        return store[0];
    }

    function _validateStrategyVaultSettings(
        StrategyVaultSettings memory settings, 
        uint32 maxOracleQueryWindow
    ) internal pure {
        require(settings.oracleWindowInSeconds <= maxOracleQueryWindow);
        require(settings.settlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.postMaturitySettlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.balancerOracleWeight <= Constants.VAULT_PERCENT_BASIS);
        require(settings.maxBalancerPoolShare <= Constants.VAULT_PERCENT_BASIS);
        require(settings.settlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);
        require(settings.postMaturitySettlementSlippageLimitPercent <= Constants.VAULT_PERCENT_BASIS);
        require(settings.feePercentage <= Constants.VAULT_PERCENT_BASIS);
    }

    function _setStrategyVaultSettings(StrategyVaultSettings memory settings) internal {
        mapping(uint256 => StrategyVaultSettings) storage store = LibBalancerStorage.getStrategyVaultSettings();
        store[0] = settings;
    }

    function _getStrategyVaultState() internal view returns (StrategyVaultState memory) {
        mapping(uint256 => StrategyVaultState) storage store = LibBalancerStorage.getStrategyVaultState();
        return store[0];
    }

    function _setStrategyVaultState(StrategyVaultState memory state) internal {
        mapping(uint256 => StrategyVaultState) storage store = LibBalancerStorage.getStrategyVaultState();
        store[0] = state;
    }

    function _getSettlementState(uint256 maturity) internal view returns (SettlementState memory) {
        mapping(uint256 => SettlementState) storage store = LibBalancerStorage.getSettlementState();
        return store[maturity];
    }

    function _setSettlementState(uint256 maturity, SettlementState memory state) internal {
        mapping(uint256 => SettlementState) storage store = LibBalancerStorage.getSettlementState();
        store[maturity] = state;
    }

    function _getBPTHeldInMaturity(
        StrategyVaultState memory strategyVaultState, 
        uint256 totalSupplyInMaturity,
        uint256 totalBPTHeld
    ) internal pure returns (uint256 bptHeldInMaturity) {
        if (strategyVaultState.totalStrategyTokenGlobal == 0) return 0;
        bptHeldInMaturity =
            (totalBPTHeld * totalSupplyInMaturity) /
            strategyVaultState.totalStrategyTokenGlobal;
    }

    function _bptThreshold(StrategyVaultSettings memory strategyVaultSettings, uint256 totalBPTSupply) 
        internal pure returns (uint256) {
        return (totalBPTSupply * strategyVaultSettings.maxBalancerPoolShare) / Constants.VAULT_PERCENT_BASIS;
    }
}
