// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {TwoTokenPoolMixin} from "./TwoTokenPoolMixin.sol";
import {TwoTokenPoolContext, WeightedOracleContext} from "../BalancerVaultTypes.sol";
import {IWeightedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {OracleMixin} from "./OracleMixin.sol";

abstract contract Weighted2TokenVaultMixin is TwoTokenPoolMixin, OracleMixin {
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
        
    constructor(
        address underlyingToken, 
        bytes32 balancerPoolId,
        uint16 secondaryBorrowCurrencyId
    ) 
        TwoTokenPoolMixin(underlyingToken, balancerPoolId, secondaryBorrowCurrencyId) 
        OracleMixin(address(BALANCER_POOL_TOKEN)) 
    {
        // The oracle is required for the vault to behave properly
        (/* */, /* */, /* */, /* */, bool oracleEnabled, /* */) 
            = IWeightedPool(address(BALANCER_POOL_TOKEN)).getMiscData();
        require(oracleEnabled);

        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - PRIMARY_INDEX;
        }

        uint256[] memory weights = IWeightedPool(address(BALANCER_POOL_TOKEN)).getNormalizedWeights();

        PRIMARY_WEIGHT = weights[PRIMARY_INDEX];
        SECONDARY_WEIGHT = weights[secondaryIndex];
    }

    function _weightedOracleContext() internal view returns (WeightedOracleContext memory) {
        return WeightedOracleContext({
            primaryWeight: PRIMARY_WEIGHT,
            secondaryWeight: SECONDARY_WEIGHT,
            baseContext: _oracleContext()
        });
    }
}
