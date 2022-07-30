// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {TwoTokenPoolMixin} from "./TwoTokenPoolMixin.sol";
import {TwoTokenPoolContext, WeightedOracleContext} from "../BalancerVaultTypes.sol";
import {IWeightedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {BalancerOracleMixin} from "./BalancerOracleMixin.sol";

abstract contract Weighted2TokenVaultMixin is TwoTokenPoolMixin, BalancerOracleMixin {
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
        
    constructor(
        uint16 primaryBorrowCurrencyId, 
        bytes32 balancerPoolId,
        uint16 secondaryBorrowCurrencyId
    ) 
        TwoTokenPoolMixin(primaryBorrowCurrencyId, balancerPoolId, secondaryBorrowCurrencyId) 
        BalancerOracleMixin(balancerPoolId) 
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
        uint256[] memory weights = new uint256[](2);
        weights[PRIMARY_INDEX] = PRIMARY_WEIGHT;
        weights[SECONDARY_INDEX] = SECONDARY_WEIGHT;

        return WeightedOracleContext({
            weights: weights,
            baseOracle: _oracleContext()
        });
    }
}
