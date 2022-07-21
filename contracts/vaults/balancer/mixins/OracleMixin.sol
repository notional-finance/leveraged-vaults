// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {StrategyVaultSettings, OracleContext} from "../BalancerVaultTypes.sol";
import {LibBalancerStorage} from "../internal/LibBalancerStorage.sol";

abstract contract OracleMixin {
    uint256 internal immutable MAX_ORACLE_QUERY_WINDOW;

    constructor(address balancerPool) {
        MAX_ORACLE_QUERY_WINDOW = IPriceOracle(balancerPool).getLargestSafeQueryWindow();
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
