// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    OracleContext, 
    TwoTokenPoolContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/TwoTokenPoolUtils.sol";

contract MockTwoTokenPoolUtils {
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    function getTimeWeightedPrimaryBalance(
        TwoTokenPoolContext memory poolContext,
        OracleContext memory oracleContext,
        uint256 bptAmount
    ) internal view returns (uint256) {
        return poolContext._getTimeWeightedPrimaryBalance(oracleContext, bptAmount);
    } 
}
