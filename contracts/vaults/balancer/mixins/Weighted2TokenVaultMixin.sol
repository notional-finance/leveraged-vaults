// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IWeightedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";

abstract contract Weighted2TokenVaultMixin {
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
    uint256 internal immutable MAX_ORACLE_QUERY_WINDOW;

    constructor(address balancerPool, uint8 primaryIndex) {
        // The oracle is required for the vault to behave properly
        (/* */, /* */, /* */, /* */, bool oracleEnabled, /* */) = IWeightedPool(balancerPool).getMiscData();
        require(oracleEnabled);

        MAX_ORACLE_QUERY_WINDOW = IPriceOracle(balancerPool).getLargestSafeQueryWindow();
        require(MAX_ORACLE_QUERY_WINDOW <= type(uint32).max); /// @dev largestQueryWindow overflow

        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - primaryIndex;
        }

        uint256[] memory weights = IWeightedPool(balancerPool).getNormalizedWeights();

        PRIMARY_WEIGHT = weights[primaryIndex];
        SECONDARY_WEIGHT = weights[secondaryIndex];
    }
}
