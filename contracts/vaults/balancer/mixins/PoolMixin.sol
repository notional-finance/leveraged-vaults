// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {PoolContext} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "../BalancerUtils.sol";

abstract contract PoolMixin {
    bytes32 internal immutable BALANCER_POOL_ID;
    IERC20 internal immutable BALANCER_POOL_TOKEN;

    constructor(bytes32 balancerPoolId) {
        BALANCER_POOL_ID = balancerPoolId;
        {
            (address pool, /* */) = BalancerUtils.BALANCER_VAULT.getPool(BALANCER_POOL_ID);
            BALANCER_POOL_TOKEN = IERC20(pool);
        }
    }

    function _poolContext() internal view returns (PoolContext memory) {
        return PoolContext({
            pool: BALANCER_POOL_TOKEN,
            poolId: BALANCER_POOL_ID
        });
    }
}
