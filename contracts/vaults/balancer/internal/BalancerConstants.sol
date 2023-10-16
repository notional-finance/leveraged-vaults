// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.17;

/**
 * Balancer specific constants
 */
library BalancerConstants {
    /// @notice Balancer pool precision
    uint256 internal constant BALANCER_PRECISION = 1e18;
    /// @notice Balancer pool precision squared, used to make calculations easier
    uint256 internal constant BALANCER_PRECISION_SQUARED = 1e36;
}
