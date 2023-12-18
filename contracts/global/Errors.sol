// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

/**
 * Common vault errors
 */
library Errors {
    /// @notice Pool price deviates too much from the oracle price
    error InvalidPrice(uint256 oraclePrice, uint256 poolPrice);
    /// @notice The provided slippage is above the configured limit
    error SlippageTooHigh(uint256 slippage, uint32 limit);
    /// @notice Attemping to trade an invalid token
    error InvalidRewardToken(address token);
    /// @notice The vault occupies too much of the underlying pool
    error PoolShareTooHigh(uint256 totalPoolClaim, uint256 poolClaimThreshold);
    /// @notice Staking operation failed
    error StakeFailed();
    /// @notice Unstaking operation failed
    error UnstakeFailed();
    /// @notice Zero pool claim returned due to rounding error
    error ZeroPoolClaim();
    /// @notice Zero vault shares returned due to rounding error
    error ZeroStrategyTokens();
    /// @notice Operation is only permitted when the vault is unlocked
    error VaultLocked();
    /// @notice Operation is only permitted when the vault is locked
    error VaultNotLocked();
    /// @notice Trading through the specified dex is not permitted
    error InvalidDexId(uint256 dexId);
}
