// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyVaultSettings} from "./VaultTypes.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

/** 
 * Common events emitted by strategy vaults
 */
library VaultEvents {
    /// @notice Emitted when reward tokens are reinvested
    event RewardReinvested(address token, uint256 amountSold, uint256 poolClaimAmount);
    /// @notice Emitted when vault settings are updated
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);
    /// @notice Emitted after an emergency exit
    event EmergencyExit(uint256 poolClaimToSettle);
    /// @notice Emitted when the vault is locked
    event VaultLocked();
    /// @notice Emitted when the vault is unlocked
    event VaultUnlocked();
}
