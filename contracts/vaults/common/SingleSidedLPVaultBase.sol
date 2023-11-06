// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {Errors} from "../../global/Errors.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {StrategyVaultState} from "./VaultTypes.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {VaultConstants} from "./VaultConstants.sol";

import {
    ISingleSidedLPStrategyVault,
    StrategyVaultSettings,
    InitParams
} from "../../../interfaces/notional/ISingleSidedLPStrategyVault.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";

/**
 * Base vault contract that implements common utility functions
 */
abstract contract SingleSidedLPVaultBase is BaseStrategyVault, UUPSUpgradeable, ISingleSidedLPStrategyVault {
    using VaultStorage for StrategyVaultState;

    constructor(NotionalProxy notional_, ITradingModule tradingModule_) 
        BaseStrategyVault(notional_, tradingModule_) { }

    function isLocked() public view returns (bool) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        return _hasFlag(state.flags, VaultConstants.FLAG_LOCKED);
    }

    /// @notice Allows the function to execute only when the vault is not locked
    modifier whenNotLocked() {
        if (isLocked()) revert Errors.VaultLocked();
        _;
    }

    /// @notice Allows the function to execute only when the vault is locked
    modifier whenLocked() {
        if (!isLocked()) revert Errors.VaultNotLocked();
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

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings) external onlyNotionalOwner {
        // Settings are validated in setStrategyVaultSettings
        VaultStorage.setStrategyVaultSettings(settings);
    }

    /// @notice Initializes the strategy
    /// @param params init parameters
    function initialize(InitParams calldata params) external override initializer onlyNotionalOwner {
        // Initialize the base vault
        __INIT_VAULT(params.name, params.borrowCurrencyId);

        // Settings are validated in setStrategyVaultSettings
        VaultStorage.setStrategyVaultSettings(params.settings);

        _initialApproveTokens();
    }

    /// @notice Allows the emergency exit role to trigger an emergency exit on the vault.
    /// In this situation, the `claimToExit` is withdrawn proportionally to the underlying
    /// tokens and held on the vault. The vault is locked so that no entries, exits or
    /// valuations of vaultShares can be performed.
    /// @param claimToExit if this is set to zero, the entire pool claim is withdrawn
    /// @param data arbitrary data passed to the implementation
    function emergencyExit(
        uint256 claimToExit, bytes calldata data
    ) external override onlyRole(EMERGENCY_EXIT_ROLE) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        if (claimToExit == 0) claimToExit = state.totalPoolClaim;

        // TODO: replace this with unstakeAndExitPool
        _emergencyExitPoolClaim(claimToExit, data);

        state.totalPoolClaim = state.totalPoolClaim - claimToExit;
        state.setStrategyVaultState();

        emit VaultEvents.EmergencyExit(claimToExit);
        _lockVault();
    }

    /// @notice Restores withdrawn tokens from emergencyExit back into the vault proportionally.
    /// Unlocks the vault after restoration so that normal functionality is restored.
    /// @param minPoolClaim slippage limit to prevent front running
    /// @param data arbitrary data passed to the implementation
    function restoreVault(
        uint256 minPoolClaim, bytes calldata data
    ) external override whenLocked onlyNotionalOwner {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();

        // TODO: replace this joinPoolAndStake
        uint256 poolTokens = _restoreVault(minPoolClaim, data);

        state.totalPoolClaim = state.totalPoolClaim + poolTokens;
        state.setStrategyVaultState(); 

        _unlockVault();
    }

    // /// @notice Reverts if the vault is locked during emergency exit.
    // function convertStrategyToUnderlying(
    //     address /* */, uint256 vaultShares, uint256 /* */
    // ) external view override whenNotLocked returns (int256 underlyingValue) {
    //     // NOTE: much of this code is in StrategyUtils.....
    //     // TODO: getPoolClaim
    //     // TODO: checkPriceLimit
    //     // TODO: valueInUnderlying
    // }

    // function _depositFromNotional(
    //     address /* account */, uint256 deposit, uint256 /* maturity */, bytes calldata data
    // ) internal override whenNotLocked returns (uint256 vaultSharesMinted) {
    //     // TODO: decode data
    //     // TODO: handle deposit trades
    //     // TODO: join pool and stake

    //     _mintStrategyTokens(lpTokens);
    // }

    // function _redeemFromNotional(
    //     address /* account */, uint256 vaultShares, uint256 /* maturity */, bytes calldata data
    // ) internal override whenNotLocked returns (uint256 finalPrimaryBalance) {
    //     _redeemStrategyTokens(vaultShares);

    //     // TODO: decode data
    //     // TODO: unstakeAndExitPool
    //     // TODO: handle exit trades
    // }

    function claimRewardTokens() external override onlyRole(REWARD_REINVESTMENT_ROLE) {
        _claimRewardTokens();
    }


    // reinvestReward
    //    - this needs the most refactoring probably....


    /// @notice Called once during initialization to set the initial token approvals.
    function _initialApproveTokens() internal virtual;

    /// @notice Called to exit pool tokens during an emergency
    function _emergencyExitPoolClaim(uint256 claimToExit, bytes calldata data) internal virtual;

    /// @notice Called to restore exited pool tokens after an emergency passes
    function _restoreVault(uint256 minPoolClaim, bytes calldata data) internal virtual returns (uint256 poolTokens);

    /// @notice Called to claim reward tokens
    function _claimRewardTokens() internal virtual;

    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}