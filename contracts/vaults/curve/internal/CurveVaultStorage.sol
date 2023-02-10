// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyVaultSettings, StrategyVaultState} from "../../common/VaultTypes.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {CurveConstants} from "./CurveConstants.sol";

library CurveVaultStorage {
    uint256 private constant STRATEGY_VAULT_SETTINGS_SLOT = 1000001;
    uint256 private constant STRATEGY_VAULT_STATE_SLOT    = 1000002;

    function _settings() private pure returns (mapping(uint256 => StrategyVaultSettings) storage store) {
        assembly { store.slot := STRATEGY_VAULT_SETTINGS_SLOT }
    }

    function _state() private pure returns (mapping(uint256 => StrategyVaultState) storage store) {
        assembly { store.slot := STRATEGY_VAULT_STATE_SLOT }
    }

    function getStrategyVaultSettings() internal view returns (StrategyVaultSettings memory) {
        // Hardcode to the zero slot
        return _settings()[0];
    }

    function setStrategyVaultSettings(StrategyVaultSettings memory settings) internal {

        mapping(uint256 => StrategyVaultSettings) storage store = _settings();
        // Hardcode to the zero slot
        store[0] = settings;

        emit VaultEvents.StrategyVaultSettingsUpdated(settings);
    }

    function getStrategyVaultState() internal view returns (StrategyVaultState memory) {
        // Hardcode to the zero slot
        return _state()[0];
    }

    function setStrategyVaultState(StrategyVaultState memory state) internal {
        mapping(uint256 => StrategyVaultState) storage store = _state();
        // Hardcode to the zero slot
        store[0] = state;
    }
}