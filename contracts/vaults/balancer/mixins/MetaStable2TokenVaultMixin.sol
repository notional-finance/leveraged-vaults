// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IMetaStablePool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {Stable2TokenOracleContext} from "../BalancerVaultTypes.sol";
import {OracleMixin} from "./OracleMixin.sol";
import {TwoTokenPoolMixin} from "./TwoTokenPoolMixin.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";

abstract contract MetaStable2TokenVaultMixin is TwoTokenPoolMixin, OracleMixin {
    constructor(
        uint16 primaryBorrowCurrencyId, 
        bytes32 balancerPoolId,
        uint16 secondaryBorrowCurrencyId
    )
        TwoTokenPoolMixin(primaryBorrowCurrencyId, balancerPoolId, secondaryBorrowCurrencyId)
        OracleMixin(balancerPoolId) 
    {
        // The oracle is required for the vault to behave properly
        (/* */, /* */, /* */, /* */, bool oracleEnabled) = 
            IMetaStablePool(address(BALANCER_POOL_TOKEN)).getOracleMiscData();
        require(oracleEnabled);
    }

    function _stable2TokenOracleContext() internal view returns (Stable2TokenOracleContext memory) {
        (
            uint256 value,
            /* bool isUpdating */,
            /* uint256 precision */
        ) = IMetaStablePool(address(BALANCER_POOL_TOKEN)).getAmplificationParameter();
        
        return Stable2TokenOracleContext({
            ampParam: value,
            baseOracle: _oracleContext()
        });
    }
}
