// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {TokenUtils, IERC20} from "@contracts/utils/TokenUtils.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "@interfaces/convex/IConvexBooster.sol";
import {IConvexRewardToken} from "@interfaces/convex/IConvexRewardToken.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "@interfaces/convex/IConvexRewardPool.sol";
import {Curve2TokenPoolMixin, DeploymentParams} from "./Curve2TokenPoolMixin.sol";
import {RewardPoolStorage, RewardPoolType} from "@contracts/vaults/common/VaultStorage.sol";

struct ConvexVaultDeploymentParams {
    address rewardPool;
    DeploymentParams baseParams;
}

abstract contract ConvexStakingMixin is Curve2TokenPoolMixin {
    using TokenUtils for IERC20;

    /// @notice Convex booster contract used for staking BPT
    address internal immutable CONVEX_BOOSTER;
    /// @notice Convex reward pool contract used for unstaking and claiming reward tokens
    address internal immutable CONVEX_REWARD_POOL;
    uint256 internal immutable CONVEX_POOL_ID;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        Curve2TokenPoolMixin(notional_, params.baseParams) {
        CONVEX_REWARD_POOL = params.rewardPool;

        address convexBooster;
        uint256 poolId;

        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            IConvexRewardPool rewardPool = IConvexRewardPool(CONVEX_REWARD_POOL);

            convexBooster = rewardPool.operator();
            poolId = rewardPool.pid();

        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            IConvexRewardPoolArbitrum rewardPool = IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL);

            convexBooster = rewardPool.convexBooster();
            poolId = rewardPool.convexPoolId();
        } else {
            revert("Unsupported chain");
        }

        CONVEX_POOL_ID = poolId;
        CONVEX_BOOSTER = convexBooster;
    }

    function _stakeLpTokens(uint256 lpTokens) internal override {
        // Method signatures are slightly different on mainnet and arbitrum
        bool success;
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            success = IConvexBooster(CONVEX_BOOSTER).deposit(CONVEX_POOL_ID, lpTokens, true);
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            success = IConvexBoosterArbitrum(CONVEX_BOOSTER).deposit(CONVEX_POOL_ID, lpTokens);
        }
        require(success);
    }

    function _unstakeLpTokens(uint256 poolClaim) internal override {
        bool success;
        // Do not claim rewards when unstaking
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            success = IConvexRewardPool(CONVEX_REWARD_POOL).withdrawAndUnwrap(poolClaim, false);
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            success = IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL).withdraw(poolClaim, false);
        }
        require(success);
    }

    function _initialApproveTokens() internal override {
        // If either token is Deployments.ETH_ADDRESS the check approve will short circuit
        IERC20(TOKEN_1).checkApprove(address(CURVE_POOL), type(uint256).max);
        IERC20(TOKEN_2).checkApprove(address(CURVE_POOL), type(uint256).max);
        CURVE_POOL_TOKEN.checkApprove(address(CONVEX_BOOSTER), type(uint256).max);
    }

    function _isInvalidRewardToken(address token) internal override view returns (bool) {
        // ETH is also at address(0) but that is never given out as a reward token
        if (WHITELISTED_REWARD != address(0) && token == WHITELISTED_REWARD) return false;

        return (
            token == TOKEN_1 ||
            token == TOKEN_2 ||
            token == address(CURVE_POOL_TOKEN) ||
            token == address(CONVEX_REWARD_POOL) ||
            token == address(CONVEX_BOOSTER) ||
            token == address(Deployments.ETH_ADDRESS) ||
            token == address(Deployments.WETH)
        );
    }

    function _rewardPoolStorage() internal view override returns (RewardPoolStorage memory r) {
        r.rewardPool = address(CONVEX_REWARD_POOL);
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            r.poolType = RewardPoolType.CONVEX_MAINNET;
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            r.poolType = RewardPoolType.CONVEX_ARBITRUM;
        } else {
            revert();
        }
    }
}