// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {ILiquidityGauge} from "../../../../interfaces/balancer/ILiquidityGauge.sol";
import {IAuraBooster} from "../../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../../interfaces/aura/IAuraRewardPool.sol";
import {IAuraStakingProxy} from "../../../../interfaces/aura/IAuraStakingProxy.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

abstract contract AuraStakingMixin {
    ILiquidityGauge internal immutable LIQUIDITY_GAUGE;
    IAuraBooster internal immutable AURA_BOOSTER;
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    uint256 internal immutable AURA_POOL_ID;
    IERC20 internal immutable BAL_TOKEN;
    IERC20 internal immutable AURA_TOKEN;

    constructor(ILiquidityGauge liquidityGauge, IAuraRewardPool auraRewardPool) {
        LIQUIDITY_GAUGE = liquidityGauge;
        AURA_REWARD_POOL = auraRewardPool;
        AURA_BOOSTER = IAuraBooster(AURA_REWARD_POOL.operator());
        AURA_POOL_ID = AURA_REWARD_POOL.pid();

        IAuraStakingProxy stakingProxy = IAuraStakingProxy(AURA_BOOSTER.stakerRewards());
        BAL_TOKEN = IERC20(stakingProxy.crv());
        AURA_TOKEN = IERC20(stakingProxy.cvx());
    }
}
