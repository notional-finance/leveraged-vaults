// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {StrategyVaultSettings, StrategyVaultState} from "@interfaces/notional/ISingleSidedLPStrategyVault.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {
    VaultRewardState,
    RewardPoolStorage,
    RewardPoolType
} from "@interfaces/notional/IVaultRewarder.sol";
import {
    WithdrawRequest,
    SplitWithdrawRequest
} from "@interfaces/notional/IWithdrawRequest.sol";

library VaultStorage {
    /// @notice Emitted when vault settings are updated
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);
    // Wrap timestamp in a struct so that it can be passed around as a storage pointer
    struct LastClaimTimestamp { uint256 value; }

    /// @notice Storage slot for vault settings
    uint256 private constant STRATEGY_VAULT_SETTINGS_SLOT = 1000001;
    /// @notice Storage slot for vault state
    uint256 private constant STRATEGY_VAULT_STATE_SLOT    = 1000002;
    /// @notice Storage slot for rewarder settings
    uint256 private constant REWARD_STATE_SLOT            = 1000003;
    /// @notice Storage slot for rewarder settings
    uint256 private constant REWARD_DEBT_SLOT             = 1000004;
    /// @notice Storage slot for reward pool type
    uint256 private constant REWARD_POOL_SLOT             = 1000005;
    /// @notice Storage slot for vault proxy holder => account
    uint256 private constant HOLDER_FOR_ACCOUNT_SLOT      = 1000006;
    /// @notice Storage slot for account => vault proxy holder
    uint256 private constant ACCOUNT_FOR_HOLDER_SLOT      = 1000007;

    /// @notice account initiated WithdrawRequest
    uint256 private constant ACCOUNT_WITHDRAW_SLOT        = 1000008;
    /// @notice Storage slot for split withdraw requests
    uint256 private constant SPLIT_WITHDRAW_SLOT          = 1000009;
    /// @notice Storage slot for withdraw request metadata
    uint256 private constant WITHDRAW_REQUEST_DATA_SLOT   = 1000010;
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

    function _rewardPool() private pure returns (mapping(uint256 => RewardPoolStorage) storage store) {
        // Assign storage slot
        assembly { store.slot := REWARD_POOL_SLOT }
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
        require(settings.maxPoolShare <= Constants.VAULT_PERCENT_BASIS);
        require(settings.oraclePriceDeviationLimitPercent <= Constants.VAULT_PERCENT_BASIS);

        mapping(uint256 => StrategyVaultSettings) storage store = _settings();
        // Hardcode to the zero slot
        store[0] = settings;

        emit StrategyVaultSettingsUpdated(settings);
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

    function getVaultRewardState() internal pure returns (mapping(uint256 => VaultRewardState) storage store) {
        // Assign storage slot
        assembly { store.slot := REWARD_STATE_SLOT }
    }

    function getAccountRewardDebt() internal pure returns (mapping(address => mapping(address => uint256)) storage store) {
        // Assign storage slot
        assembly { store.slot := REWARD_DEBT_SLOT }
    }

    function getRewardPoolStorage() internal view returns (RewardPoolStorage memory) {
        return _rewardPool()[0];
    }

    function setRewardPoolStorage(RewardPoolStorage memory r) internal {
        _rewardPool()[0] = r;
    }

    function getHolderForAccount() internal pure returns (mapping(address => address) storage store) {
        assembly { store.slot := HOLDER_FOR_ACCOUNT_SLOT }
    }

    function getAccountForHolder() internal pure returns (mapping(address => address) storage store) {
        assembly { store.slot := ACCOUNT_FOR_HOLDER_SLOT }
    }

    function getAccountWithdrawRequest() internal pure returns (mapping(address => WithdrawRequest) storage store) {
        assembly { store.slot := ACCOUNT_WITHDRAW_SLOT }
    }

    function getSplitWithdrawRequest() internal pure returns (mapping(uint256 => SplitWithdrawRequest) storage store) {
        assembly { store.slot := SPLIT_WITHDRAW_SLOT }
    }

    function getWithdrawRequestData() internal pure returns (mapping(uint256 => bytes) storage store) {
        assembly { store.slot := WITHDRAW_REQUEST_DATA_SLOT }
    }
}
