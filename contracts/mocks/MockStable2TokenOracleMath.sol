// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StableOracleContext, 
    OracleContext, 
    TwoTokenPoolContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Stable2TokenOracleMath} from "../vaults/balancer/internal/Stable2TokenOracleMath.sol";

contract MockStable2TokenOracleMath {
    using Stable2TokenOracleMath for StableOracleContext;

    function getSpotPrice(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 tokenIndex
    ) external view returns (uint256 spotPrice) {
        return oracleContext._getSpotPrice(poolContext, tokenIndex);
    }

    function getOptimalSecondaryBorrowAmount(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount
    ) external view returns (uint256) {
        return oracleContext._getOptimalSecondaryBorrowAmount(poolContext, primaryAmount);
    }  
}
