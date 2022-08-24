// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IMetaStablePool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {StableOracleContext} from "../BalancerVaultTypes.sol";
import {BalancerOracleMixin} from "./BalancerOracleMixin.sol";
import {TwoTokenPoolMixin} from "./TwoTokenPoolMixin.sol";
import {DeploymentParams} from "../BalancerVaultTypes.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";

abstract contract MetaStable2TokenVaultMixin is TwoTokenPoolMixin, BalancerOracleMixin {
    constructor(
        NotionalProxy notional_, 
        DeploymentParams memory params,
        uint16 primaryBorrowCurrencyId, 
        bytes32 balancerPoolId
    )
        TwoTokenPoolMixin(notional_, params, primaryBorrowCurrencyId, balancerPoolId)
        BalancerOracleMixin(balancerPoolId) 
    {
        // The oracle is required for the vault to behave properly
        (/* */, /* */, /* */, /* */, bool oracleEnabled) = 
            IMetaStablePool(address(BALANCER_POOL_TOKEN)).getOracleMiscData();
        require(oracleEnabled);
    }

    function _stableOracleContext() internal view returns (StableOracleContext memory) {
        (
            uint256 value,
            /* bool isUpdating */,
            /* uint256 precision */
        ) = IMetaStablePool(address(BALANCER_POOL_TOKEN)).getAmplificationParameter();
        
        return StableOracleContext({
            ampParam: value,
            baseOracle: _oracleContext()
        });
    }
}
