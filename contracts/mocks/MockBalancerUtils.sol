// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {WeightedOracleContext} from "../vaults/balancer/BalancerVaultTypes.sol";
import {BalancerUtils} from "../vaults/balancer/BalancerUtils.sol";

contract MockBalancerUtils {
    function getOptimalSecondaryBorrowAmount(
        WeightedOracleContext memory context,
        uint256 primaryAmount
    ) external view returns (uint256) {
        return BalancerUtils.getOptimalSecondaryBorrowAmount(context, primaryAmount);
    }

    function getSpotPrice(WeightedOracleContext memory context, uint256 tokenIndex) 
        external view returns (uint256 spotPrice) {
        return BalancerUtils.getSpotPrice(context, tokenIndex);
    }

    function getTimeWeightedPrimaryBalance(WeightedOracleContext memory context, uint256 bptAmount) 
        internal view returns (uint256 primaryAmount) {
        return BalancerUtils.getTimeWeightedPrimaryBalance(context, bptAmount);
    }
}
