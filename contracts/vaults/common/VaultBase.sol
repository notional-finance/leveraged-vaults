// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";
import {Errors} from "../../global/Errors.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {StrategyVaultState} from "./VaultTypes.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {VaultConstants} from "./VaultConstants.sol";

/**
 * Base vault contract that implements common utility functions
 */
abstract contract VaultBase is BaseStrategyVault, UUPSUpgradeable {

    constructor(NotionalProxy notional_, ITradingModule tradingModule_) 
        BaseStrategyVault(notional_, tradingModule_) { }

    function _isLocked() internal view returns (bool) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        return _hasFlag(state.flags, VaultConstants.FLAG_LOCKED);
    }

    /// @notice Allows the function to execute only when the vault is not locked
    modifier whenNotLocked() {
        if (_isLocked()) revert Errors.VaultLocked();
        _;
    }

    /// @notice Allows the function to execute only when the vault is locked
    modifier whenLocked() {
        if (!_isLocked()) revert Errors.VaultNotLocked();
        _;
    }

    /// @notice Checks if a flag bit is set
    /// @param flags 32-bit flags
    /// @param flagID flag mask
    /// @return true if the flag is set, false otherwise
    function _hasFlag(uint32 flags, uint32 flagID) private pure returns (bool) {
        return (flags & flagID) == flagID;
    }

    /// @notice Locks the vault, preventing deposits and redemptions
    function _lockVault() internal {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        // Set locked flag
        state.flags = state.flags | VaultConstants.FLAG_LOCKED;
        VaultStorage.setStrategyVaultState(state);
        emit VaultEvents.VaultLocked();
    }

    /// @notice Unlocks the vault
    function _unlockVault() internal {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        // Remove locked flag
        state.flags = state.flags & ~VaultConstants.FLAG_LOCKED;
        VaultStorage.setStrategyVaultState(state);
        emit VaultEvents.VaultUnlocked();
    }

    /// @notice Allow Notional owner to upgrade the contract
    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
    
    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}