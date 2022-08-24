// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {PoolContext} from "../BalancerVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {BalancerStrategyBase} from "../BalancerStrategyBase.sol";
import {DeploymentParams} from "../BalancerVaultTypes.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";

abstract contract PoolMixin is BalancerStrategyBase {
    bytes32 internal immutable BALANCER_POOL_ID;
    IERC20 internal immutable BALANCER_POOL_TOKEN;

    constructor(NotionalProxy notional_, DeploymentParams memory params, bytes32 balancerPoolId) 
        BalancerStrategyBase(notional_, params) {
        BALANCER_POOL_ID = balancerPoolId;
        (address pool, /* */) = Deployments.BALANCER_VAULT.getPool(balancerPoolId);
        BALANCER_POOL_TOKEN = IERC20(pool);
    }

    function _poolContext() internal view returns (PoolContext memory) {
        return PoolContext({
            pool: BALANCER_POOL_TOKEN,
            poolId: BALANCER_POOL_ID
        });
    }
}
