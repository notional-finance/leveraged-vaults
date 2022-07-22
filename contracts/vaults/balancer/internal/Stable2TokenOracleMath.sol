// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StableOracleContext, TwoTokenPoolContext} from "../BalancerVaultTypes.sol";

library Stable2TokenOracleMath {
    function getSpotPrice(
        StableOracleContext memory oracleContext, 
        TwoTokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {

    }

    /// @notice Returns the optimal amount to borrow for the secondary token
    /// @param oracleContext oracle context variables
    /// @param poolContext oracle context variables
    /// @return secondaryAmount optimal amount of the secondary token to join the pool
    function getOptimalSecondaryBorrowAmount(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount
    ) internal view returns (uint256 secondaryAmount) {
    
    }
}
