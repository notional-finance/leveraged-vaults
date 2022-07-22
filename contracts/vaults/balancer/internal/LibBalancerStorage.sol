// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;
pragma abicoder v2;

import {StrategyVaultSettings, StrategyVaultState, SettlementState} from "../BalancerVaultTypes.sol";

library LibBalancerStorage {

    /// @dev Offset for the initial slot in lib storage, gives us this number of storage slots
    /// available in StorageLayoutV1 and all subsequent storage layouts that inherit from it.
    uint256 private constant STORAGE_SLOT_BASE = 1000000;

    /// @dev Storage IDs for storage buckets. Each id maps to an internal storage
    /// slot used for a particular mapping
    ///     WARNING: APPEND ONLY
    enum StorageId {
        Unused,
        StrategyVaultSettings,
        StrategyVaultState,
        SettlementState
    }

    /// @dev 
    function getStrategyVaultSettings() internal pure returns (
        mapping(uint256 => StrategyVaultSettings) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.StrategyVaultSettings);
        assembly { store.slot := slot }
    }

    function getStrategyVaultState() internal pure returns (
        mapping(uint256 => StrategyVaultState) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.StrategyVaultState);
        assembly { store.slot := slot }
    }

    function getSettlementState() internal pure returns (
        mapping(uint256 => SettlementState) storage store
    ) {
        uint256 slot = _getStorageSlot(StorageId.SettlementState);
        assembly { store.slot := slot }
    }

    /// @dev Get the storage slot given a storage ID.
    /// @param storageId An entry in `StorageId`
    /// @return slot The storage slot.
    function _getStorageSlot(StorageId storageId)
        private
        pure
        returns (uint256 slot)
    {
        // This should never overflow with a reasonable `STORAGE_SLOT_EXP`
        // because Solidity will do a range check on `storageId` during the cast.
        return uint256(storageId) + STORAGE_SLOT_BASE;
    }
} 