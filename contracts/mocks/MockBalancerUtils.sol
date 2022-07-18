// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {OracleContext} from "../vaults/balancer/BalancerVaultTypes.sol";
import {BalancerUtils} from "../vaults/balancer/BalancerUtils.sol";

contract MockBalancerUtils {
    function getOptimalSecondaryBorrowAmount(
        OracleContext memory context,
        uint256 primaryAmount
    ) external view returns (uint256) {
        return BalancerUtils.getOptimalSecondaryBorrowAmount(context, primaryAmount);
    }

    function getSpotPrice(OracleContext memory context, uint256 tokenIndex) 
        external view returns (uint256 spotPrice) {
        return BalancerUtils.getSpotPrice(context, tokenIndex);
    }
}
