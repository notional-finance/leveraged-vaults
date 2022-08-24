// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {StrategyVaultSettings, OracleContext} from "../BalancerVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {BalancerVaultStorage} from "../internal/BalancerVaultStorage.sol";

abstract contract BalancerOracleMixin {
    uint32 internal immutable MAX_ORACLE_QUERY_WINDOW;

    constructor(bytes32 balancerPoolId) {
        (address pool, /* */) = Deployments.BALANCER_VAULT.getPool(balancerPoolId);

        uint256 maxOracleQueryWindow = IPriceOracle(pool).getLargestSafeQueryWindow();
        /// @dev getLargestSafeQueryWindow overflow
        require(maxOracleQueryWindow > 0 && maxOracleQueryWindow <= type(uint32).max); 
        MAX_ORACLE_QUERY_WINDOW = uint32(maxOracleQueryWindow);
    }

    function _oracleContext() internal view returns (OracleContext memory) {
        StrategyVaultSettings memory settings = BalancerVaultStorage.getStrategyVaultSettings();
        return OracleContext({
            oracleWindowInSeconds: settings.oracleWindowInSeconds,
            balancerOracleWeight: settings.balancerOracleWeight
        });
    }
}
