// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IMetaStablePool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";

abstract contract MetaStableVaultMixin {
    uint256 internal immutable MAX_ORACLE_QUERY_WINDOW;

    constructor(address balancerPool) {
        // The oracle is required for the vault to behave properly
        (/* */, /* */, /* */, /* */, bool oracleEnabled) = IMetaStablePool(balancerPool).getOracleMiscData();
        require(oracleEnabled);

        MAX_ORACLE_QUERY_WINDOW = IPriceOracle(balancerPool).getLargestSafeQueryWindow();
        require(MAX_ORACLE_QUERY_WINDOW <= type(uint32).max); /// @dev largestQueryWindow overflow
    }
}
