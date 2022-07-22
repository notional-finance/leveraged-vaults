// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {StableOracleContext, TwoTokenPoolContext} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Stable2TokenOracleMath} from "../vaults/balancer/internal/Stable2TokenOracleMath.sol";

contract MockStable2TokenOracleMath {
    function getSpotPrice(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 tokenIndex
    ) 
        external view returns (uint256 spotPrice) {
        return Stable2TokenOracleMath.getSpotPrice(oracleContext, poolContext, tokenIndex);
    }

    function getOptimalSecondaryBorrowAmount(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount
    ) external view returns (uint256) {
        return Stable2TokenOracleMath.getOptimalSecondaryBorrowAmount(oracleContext, poolContext, primaryAmount);
    }   
}
