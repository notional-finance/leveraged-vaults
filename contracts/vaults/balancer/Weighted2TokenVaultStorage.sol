// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {DeploymentParams} from "./BalancerVaultTypes.sol";
import {BalancerVaultStorage} from "./BalancerVaultStorage.sol";
import {IWeightedPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";

abstract contract Weighted2TokenVaultStorage is BalancerVaultStorage {
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
    uint256 internal immutable MAX_ORACLE_QUERY_WINDOW;

    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        BalancerVaultStorage(notional_, params) {

        // The oracle is required for the vault to behave properly
        (/* */, /* */, /* */, /* */, bool oracleEnabled, /* */) = 
            IWeightedPool(address(BALANCER_POOL_TOKEN)).getMiscData();
        require(oracleEnabled);

        MAX_ORACLE_QUERY_WINDOW = IPriceOracle(address(BALANCER_POOL_TOKEN)).getLargestSafeQueryWindow();
        require(MAX_ORACLE_QUERY_WINDOW <= type(uint32).max); /// @dev largestQueryWindow overflow

        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - PRIMARY_INDEX;
        }

        uint256[] memory weights = IWeightedPool(address(BALANCER_POOL_TOKEN)).getNormalizedWeights();

        PRIMARY_WEIGHT = weights[PRIMARY_INDEX];
        SECONDARY_WEIGHT = weights[secondaryIndex];
    }
}
