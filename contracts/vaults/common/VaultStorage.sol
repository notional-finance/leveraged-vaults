// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyVaultSettings, StrategyVaultState} from "./VaultTypes.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {VaultConstants} from "./VaultConstants.sol";

/** 
 * Common vault storage slots
 */
library VaultStorage {
    /// @notice Storage slot for vault settings
    uint256 private constant STRATEGY_VAULT_SETTINGS_SLOT = 1000001;
    /// @notice Storage slot for vault state
    uint256 private constant STRATEGY_VAULT_STATE_SLOT    = 1000002;
    /// @notice Append only

    /// @notice returns the storage slot that contains the vault settings
    function _settings() private pure returns (mapping(uint256 => StrategyVaultSettings) storage store) {
        // Assign storage slot
        assembly { store.slot := STRATEGY_VAULT_SETTINGS_SLOT }
    }

    /// @notice returns the storage slot that contains the vault state
    function _state() private pure returns (mapping(uint256 => StrategyVaultState) storage store) {
        // Assign storage slot
        assembly { store.slot := STRATEGY_VAULT_STATE_SLOT }
    }

    /// @notice returns strategy vault settings
    /// @return vault settings
    function getStrategyVaultSettings() internal view returns (StrategyVaultSettings memory) {
        // Hardcode to the zero slot
        return _settings()[0];
    }

    /// @notice writes the strategy vault settings to storage
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings memory settings) internal {
        // Check limits
        require(settings.maxPoolShare <= VaultConstants.VAULT_PERCENT_BASIS);
        require(settings.emergencySettlementSlippageLimitPercent <= VaultConstants.SLIPPAGE_LIMIT_PRECISION);
        require(settings.oraclePriceDeviationLimitPercent <= VaultConstants.VAULT_PERCENT_BASIS);
        require(settings.poolSlippageLimitPercent <= VaultConstants.VAULT_PERCENT_BASIS);

        mapping(uint256 => StrategyVaultSettings) storage store = _settings();
        // Hardcode to the zero slot
        store[0] = settings;

        emit VaultEvents.StrategyVaultSettingsUpdated(settings);
    }

    /// @notice returns the strategy vault state
    /// @return vault state
    function getStrategyVaultState() internal view returns (StrategyVaultState memory) {
        // Hardcode to the zero slot
        return _state()[0];
    }

    /// @notice writes the strategy vault state to storage
    /// @param state vault state
    function setStrategyVaultState(StrategyVaultState memory state) internal {
        mapping(uint256 => StrategyVaultState) storage store = _state();
        // Hardcode to the zero slot
        store[0] = state;
    }

}
