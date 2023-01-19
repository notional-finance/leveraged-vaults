// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ConvexStakingContext, ConvexVaultDeploymentParams} from "../CurveVaultTypes.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {StrategyVaultSettings, CurveVaultStorage} from "../internal/CurveVaultStorage.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {ICurveGauge} from "../../../../interfaces/curve/ICurveGauge.sol";
import {IConvexBooster} from "../../../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardToken} from "../../../../interfaces/convex/IConvexRewardToken.sol";
import {IConvexRewardPool} from "../../../../interfaces/convex/IConvexRewardPool.sol";
import {IConvexStakingProxy} from "../../../../interfaces/convex/IConvexStakingProxy.sol";
import {CurveConstants} from "../internal/CurveConstants.sol";
import {CurveEvents} from "../CurveEvents.sol";
import {CurveStrategyBase} from "../CurveStrategyBase.sol";

abstract contract ConvexStakingMixin is CurveStrategyBase {
    using TokenUtils for IERC20;

    /// @notice Convex booster contract used for staking BPT
    IConvexBooster internal immutable CONVEX_BOOSTER;
    /// @notice Convex reward pool contract used for unstaking and claiming reward tokens
    IConvexRewardPool internal immutable CONVEX_REWARD_POOL;
    uint256 internal immutable CONVEX_POOL_ID;
    IERC20 internal immutable CRV_TOKEN;
    IERC20 internal immutable CVX_TOKEN;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        CurveStrategyBase(notional_, params.baseParams) {
        CONVEX_REWARD_POOL = params.cvxRewardPool;
        CONVEX_BOOSTER = IConvexBooster(CONVEX_REWARD_POOL.operator());
        CONVEX_POOL_ID = CONVEX_REWARD_POOL.pid();

        IConvexStakingProxy stakingProxy = IConvexStakingProxy(CONVEX_BOOSTER.stakerRewards());
        CRV_TOKEN = IERC20(stakingProxy.rewardToken());
        CVX_TOKEN = IERC20(stakingProxy.stakingToken());
    }

    function _rewardTokens() private view returns (IERC20[] memory tokens) {
        uint256 rewardTokenCount = CONVEX_REWARD_POOL.extraRewardsLength() + 2;
        tokens = new IERC20[](rewardTokenCount);
        tokens[0] = CRV_TOKEN;
        tokens[1] = CVX_TOKEN;
        for (uint256 i = 2; i < rewardTokenCount; i++) {
            tokens[i] = IERC20(IConvexRewardToken(CONVEX_REWARD_POOL.extraRewards(i - 2)).rewardToken());
        }
    }

    function _convexStakingContext() internal view returns (ConvexStakingContext memory) {
        return ConvexStakingContext({
            cvxBooster: CONVEX_BOOSTER,
            cvxRewardPool: CONVEX_REWARD_POOL,
            cvxPoolId: CONVEX_POOL_ID,
            rewardTokens: _rewardTokens()
        });
    }

    function claimRewardTokens() 
        external onlyRole(REWARD_REINVESTMENT_ROLE) returns (uint256[] memory claimedBalances) {
        IERC20[] memory rewardTokens = _rewardTokens();

        uint256 numRewardTokens = rewardTokens.length;

        claimedBalances = new uint256[](numRewardTokens);
        for (uint256 i; i < numRewardTokens; i++) {
            claimedBalances[i] = rewardTokens[i].balanceOf(address(this));
        }

        bool success = CONVEX_REWARD_POOL.getReward(address(this), true); // claimExtraRewards = true
        require(success);

        for (uint256 i; i < numRewardTokens; i++) {
            claimedBalances[i] = rewardTokens[i].balanceOf(address(this)) - claimedBalances[i];
        }
        
        emit CurveEvents.ClaimedRewardTokens(rewardTokens, claimedBalances);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
