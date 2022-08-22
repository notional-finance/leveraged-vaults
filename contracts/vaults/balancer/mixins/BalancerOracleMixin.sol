// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {StrategyVaultSettings, OracleContext} from "../BalancerVaultTypes.sol";
import {LibBalancerStorage} from "../internal/LibBalancerStorage.sol";
import {Deployments} from "../../../global/Deployments.sol";

abstract contract BalancerOracleMixin {
    uint256 internal immutable MAX_ORACLE_QUERY_WINDOW;

    constructor(bytes32 balancerPoolId) {
        (address pool, /* */) = Deployments.BALANCER_VAULT.getPool(balancerPoolId);

        MAX_ORACLE_QUERY_WINDOW = IPriceOracle(pool).getLargestSafeQueryWindow();
        // @audit should this also be greater than zero?
        require(MAX_ORACLE_QUERY_WINDOW <= type(uint32).max); /// @dev largestQueryWindow overflow
    }

    function _oracleContext() internal view returns (OracleContext memory) {
        mapping(uint256 => StrategyVaultSettings) storage store = LibBalancerStorage.getStrategyVaultSettings();
        StrategyVaultSettings memory settings = store[0];
        return OracleContext({
            oracleWindowInSeconds: settings.oracleWindowInSeconds,
            balancerOracleWeight: settings.balancerOracleWeight
        });
    }
}
