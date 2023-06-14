// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

library VaultConstants {
    uint32 internal constant SLIPPAGE_LIMIT_PRECISION = 1e8;

    /// @notice Precision for all percentages used by the vault
    /// 1e4 = 100% (i.e. maxPoolShare)
    uint16 internal constant VAULT_PERCENT_BASIS = 1e4;
    /// @notice Buffer percentage between the desired share of the pool
    /// and the maximum share of the pool allowed by maxPoolShare 1e4 = 100%, 8e3 = 80%
    uint16 internal constant POOL_SHARE_BUFFER = 8e3;
    /// @notice Max settlement cool down period allowed (1 day)
    uint16 internal constant MAX_SETTLEMENT_COOLDOWN_IN_MINUTES = 24 * 60;

    uint32 internal constant FLAG_LOCKED = 1 << 0;
}
