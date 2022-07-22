// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {WeightedOracleContext, TwoTokenPoolContext} from "../vaults/balancer/BalancerVaultTypes.sol";
import {BalancerUtils} from "../vaults/balancer/BalancerUtils.sol";

contract MockBalancerUtils {
    function getTimeWeightedPrimaryBalance(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 bptAmount
    ) 
        internal view returns (uint256 primaryAmount) {
        return BalancerUtils.getTimeWeightedPrimaryBalance(oracleContext, poolContext, bptAmount);
    }
}
