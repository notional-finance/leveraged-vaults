// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {WeightedOracleContext, TwoTokenPoolContext} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Weighted2TokenOracleMath} from "../vaults/balancer/internal/Weighted2TokenOracleMath.sol";

contract MockWeighted2TokenOracleMath {
    function getSpotPrice(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 tokenIndex
    ) 
        external view returns (uint256 spotPrice) {
        return Weighted2TokenOracleMath.getSpotPrice(oracleContext, poolContext, tokenIndex);
    }

    function getOptimalSecondaryBorrowAmount(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount
    ) external view returns (uint256) {
        return Weighted2TokenOracleMath.getOptimalSecondaryBorrowAmount(oracleContext, poolContext, primaryAmount);
    }
}
