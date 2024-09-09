// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {IAuraBooster, IAuraBoosterLite} from "@interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "@interfaces/aura/IAuraRewardPool.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {BalancerPoolMixin, DeploymentParams} from "./BalancerPoolMixin.sol";
import {TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {RewardPoolStorage, RewardPoolType} from "@contracts/vaults/common/VaultStorage.sol";

/// @notice Deployment parameters with Aura staking
struct AuraVaultDeploymentParams {
    /// @notice Aura reward pool address
    IAuraRewardPool rewardPool;
    address whitelistedReward;
    /// @notice Base deployment parameters
    DeploymentParams baseParams;
}

abstract contract AuraStakingMixin is BalancerPoolMixin {
    using TokenUtils for IERC20;

    /// @notice Aura booster contract used for staking BPT
    IAuraBooster internal immutable AURA_BOOSTER;
    /// @notice Aura reward pool contract used for unstaking and claiming reward tokens
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    /// @notice Aura pool ID used for staking
    uint256 internal immutable AURA_POOL_ID;
    address immutable WHITELISTED_REWARD;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        BalancerPoolMixin(notional_, params.baseParams) {
        AURA_REWARD_POOL = params.rewardPool;

        if (address(AURA_REWARD_POOL) != address(0)) {
            // Skip this if there is no reward pool
            AURA_BOOSTER = IAuraBooster(AURA_REWARD_POOL.operator());
            AURA_POOL_ID = AURA_REWARD_POOL.pid();
        }
        // Allows one of the pool tokens to be whitelisted as a reward token to be re-entered
        // back into the pool to increase LP shares.
        WHITELISTED_REWARD = params.whitelistedReward;
    }

    function _isInvalidRewardToken(address token) internal override view returns (bool) {
        // ETH is also at address(0) but that is never given out as a reward token
        if (WHITELISTED_REWARD != address(0) && token == WHITELISTED_REWARD) return false;

        return (
            token == TOKEN_1 ||
            token == TOKEN_2 ||
            token == TOKEN_3 ||
            token == TOKEN_4 ||
            token == TOKEN_5 ||
            token == address(BALANCER_POOL_TOKEN) ||
            token == address(AURA_BOOSTER) ||
            token == address(AURA_REWARD_POOL) ||
            token == address(Deployments.WETH) ||
            token == address(Deployments.ETH_ADDRESS)
        );
    }

    /// @notice Called once on initialization to set token approvals
    function _initialApproveTokens() internal override {
        (IERC20[] memory tokens, /* */) = TOKENS();
        for (uint256 i; i < tokens.length; i++) {
            tokens[i].checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
        }

        // Approve Aura to transfer pool tokens for staking
        if (address(AURA_BOOSTER) != address(0)) {
            POOL_TOKEN().checkApprove(address(AURA_BOOSTER), type(uint256).max);
        }
    }

    /// @notice Claim reward tokens
    function _rewardPoolStorage() internal view override returns (RewardPoolStorage memory r) {
        r.poolType = address(AURA_REWARD_POOL) == address(0) ? RewardPoolType._UNUSED : RewardPoolType.AURA;
        r.rewardPool = address(AURA_REWARD_POOL);
    }
}