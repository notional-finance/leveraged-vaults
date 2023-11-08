// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TokenUtils, IERC20} from "../../utils/TokenUtils.sol";
import {Constants} from "../../global/Constants.sol";
import {Deployments} from "../../global/Deployments.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardToken} from "../../../interfaces/convex/IConvexRewardToken.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "../../../interfaces/convex/IConvexRewardPool.sol";
import {Curve2TokenPoolMixin, DeploymentParams} from "./Curve2TokenPoolMixin.sol";

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

    function _initialApproveTokens() internal override {
        // If either token is Deployments.ETH_ADDRESS the check approve will short circuit
        IERC20(TOKEN_1).checkApprove(address(CURVE_POOL), type(uint256).max);
        IERC20(TOKEN_2).checkApprove(address(CURVE_POOL), type(uint256).max);
        CURVE_POOL_TOKEN.checkApprove(address(CONVEX_BOOSTER), type(uint256).max);
    }

    function _validateRewardToken(address token) internal override view {
        if (
            token == TOKEN_1 ||
            token == TOKEN_2 ||
            token == address(CURVE_POOL_TOKEN) ||
            token == address(CONVEX_REWARD_POOL) ||
            token == address(CONVEX_BOOSTER) ||
            token == Deployments.ALT_ETH_ADDRESS
        ) { revert(); }
    }

    function _claimRewardTokens() internal override {
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            require(IConvexRewardPool(CONVEX_REWARD_POOL).getReward(address(this), true));
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL).getReward(address(this));
        }
        revert();
    }
}
