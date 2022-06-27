// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

struct BalancerVaultState {

}

contract BalancerVaultStorageLayoutV1 {
    /// @notice account => (maturity => balance)
    mapping(address => mapping(uint256 => uint256))
        private secondaryAmountfCashBorrowed;

    /// @notice Keeps track of the possible gauge reward tokens
    mapping(address => bool) private gaugeRewardTokens;

    /// @notice Total number of strategy tokens across all maturities
    uint256 internal totalStrategyTokenGlobal;

    uint256 internal maxUnderlyingSurplus;

    /// @notice Balancer oracle window in seconds
    uint32 internal oracleWindowInSeconds;

    // @audit marking all of these storage values as public adds a getter for each one, which
    // adds a decent amount of bytecode. consider making them internal and then creating a single
    // getter for all the parameters (or just move them into structs and mark those as public)
    uint32 internal maxBalancerPoolShare;

    /// @notice Slippage limit for normal settlement
    uint32 internal settlementSlippageLimit;

    /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
    uint32 internal emergencySettlementSlippageLimit;

    uint32 internal balancerOracleWeight;

    /// @notice Cool down in seconds for normal settlement
    // @audit this can be a smaller value in storage especially if you use minutes in storage instead
    uint16 internal settlementCoolDownInMinutes;

    /// @notice Cool down in seconds for emergency settlement
    uint16 internal postMaturitySettlementCoolDownInMinutes;

    uint32 internal lastSettlementTimestamp;

    uint32 internal lastPostMaturitySettlementTimestamp;
}