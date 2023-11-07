// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Deployments} from "../../../global/Deployments.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {AuraStakingContext, AuraVaultDeploymentParams} from "../BalancerVaultTypes.sol";
import {IAuraBooster, IAuraBoosterLite} from "../../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../../interfaces/aura/IAuraRewardPool.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {BalancerPoolMixin} from "./BalancerPoolMixin.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";

/**
 * Base class for all Aura strategies
 */
abstract contract AuraStakingMixin is BalancerPoolMixin {
    using TokenUtils for IERC20;

    /// @notice Aura booster contract used for staking BPT
    IAuraBooster internal immutable AURA_BOOSTER;
    /// @notice Aura reward pool contract used for unstaking and claiming reward tokens
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    /// @notice Aura pool ID used for staking
    uint256 internal immutable AURA_POOL_ID;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        BalancerPoolMixin(notional_, params) {
        AURA_REWARD_POOL = params.rewardPool;

        AURA_BOOSTER = IAuraBooster(AURA_REWARD_POOL.operator());
        AURA_POOL_ID = AURA_REWARD_POOL.pid();
    }

    function _initialApproveTokens() internal override {
        (IERC20[] memory tokens, /* */) = TOKENS();
        for (uint256 i; i < tokens.length; i++) {
            tokens[i].checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
        }

        // Approve Aura to transfer pool tokens for staking
        POOL_TOKEN().checkApprove(address(AURA_BOOSTER), type(uint256).max);
    }

    /// @notice Claim reward tokens
    function _claimRewardTokens() internal override {
        // Claim all reward tokens including extra tokens
        bool success = AURA_REWARD_POOL.getReward(address(this), true); // claimExtraRewards = true
        require(success);
    }
}