// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {DeploymentParams} from "./BalancerVaultTypes.sol";
import {BalancerVaultStorage} from "./BalancerVaultStorage.sol";
import {IMetaStablePool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";

abstract contract MetaStableVaultStorage is BalancerVaultStorage {
    uint256 internal immutable MAX_ORACLE_QUERY_WINDOW;

    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        BalancerVaultStorage(notional_, params) {

        // The oracle is required for the vault to behave properly
        (/* */, /* */, /* */, /* */, bool oracleEnabled) = 
            IMetaStablePool(address(BALANCER_POOL_TOKEN)).getOracleMiscData();
        require(oracleEnabled);

        MAX_ORACLE_QUERY_WINDOW = IPriceOracle(address(BALANCER_POOL_TOKEN)).getLargestSafeQueryWindow();
        require(MAX_ORACLE_QUERY_WINDOW <= type(uint32).max); /// @dev largestQueryWindow overflow
    }
}
