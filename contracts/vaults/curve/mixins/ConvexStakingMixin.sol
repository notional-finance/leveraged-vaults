// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ConvexStakingContext, ConvexVaultDeploymentParams} from "../CurveVaultTypes.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {Constants} from "../../../global/Constants.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {ICurveGauge} from "../../../../interfaces/curve/ICurveGauge.sol";
import {IConvexBooster} from "../../../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardToken} from "../../../../interfaces/convex/IConvexRewardToken.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "../../../../interfaces/convex/IConvexRewardPool.sol";
import {IConvexStakingProxy} from "../../../../interfaces/convex/IConvexStakingProxy.sol";
import {CurveConstants} from "../internal/CurveConstants.sol";
import {RewardUtils} from "../../common/internal/reward/RewardUtils.sol";
import {StrategyVaultSettings, VaultStorage} from "../../common/VaultStorage.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {VaultBase} from "../../common/VaultBase.sol";

abstract contract ConvexStakingMixin is VaultBase {
    using TokenUtils for IERC20;

    /// @notice Convex booster contract used for staking BPT
    address internal immutable CONVEX_BOOSTER;
    /// @notice Convex reward pool contract used for unstaking and claiming reward tokens
    address internal immutable CONVEX_REWARD_POOL;
    uint256 internal immutable CONVEX_POOL_ID;
    IERC20 internal immutable CRV_TOKEN;
    IERC20 internal immutable CVX_TOKEN;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        VaultBase(notional_, params.baseParams.tradingModule) {
        CONVEX_REWARD_POOL = params.rewardPool;

        address convexBooster;
        IERC20 crvToken;
        IERC20 cvxToken;
        uint256 poolId;

        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            IConvexRewardPool rewardPool = IConvexRewardPool(CONVEX_REWARD_POOL);

            convexBooster = rewardPool.operator();
            poolId = rewardPool.pid();

            IConvexStakingProxy stakingProxy = IConvexStakingProxy(IConvexBooster(convexBooster).stakerRewards());
            crvToken = IERC20(stakingProxy.rewardToken());
            cvxToken = IERC20(stakingProxy.stakingToken());
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            IConvexRewardPoolArbitrum rewardPool = IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL);

            convexBooster = rewardPool.convexBooster();
            poolId = rewardPool.convexPoolId();
        } else {
            revert("Unsupported chain");
        }

        CONVEX_POOL_ID = poolId;
        CONVEX_BOOSTER = convexBooster;
        CRV_TOKEN = crvToken;
        CVX_TOKEN = cvxToken;
    }

    function _rewardTokens() private view returns (IERC20[] memory tokens) {
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            IConvexRewardPool rewardPool = IConvexRewardPool(CONVEX_REWARD_POOL);

            uint256 rewardTokenCount = rewardPool.extraRewardsLength() + 2;
            tokens = new IERC20[](rewardTokenCount);
            tokens[0] = CRV_TOKEN;
            tokens[1] = CVX_TOKEN;
            for (uint256 i = 2; i < rewardTokenCount; i++) {
                tokens[i] = IERC20(IConvexRewardToken(rewardPool.extraRewards(i - 2)).rewardToken());
            }
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            IConvexRewardPoolArbitrum rewardPool = IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL);

            uint256 rewardTokenCount = rewardPool.rewardLength();
            tokens = new IERC20[](rewardTokenCount);
            for (uint256 i = 0; i < rewardTokenCount; i++) {
                (address token, /* */, /* */) = rewardPool.rewards(i);
                tokens[i] = IERC20(token);
            }
        } else {
            revert("Unsupported chain");
        }
    }

    function _convexStakingContext() internal view returns (ConvexStakingContext memory) {
        return ConvexStakingContext({
            booster: CONVEX_BOOSTER,
            rewardPool: CONVEX_REWARD_POOL,
            poolId: CONVEX_POOL_ID,
            rewardTokens: _rewardTokens()
        });
    }

    function _claimConvexRewardTokens() internal returns (bool) {
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {      
            return IConvexRewardPool(CONVEX_REWARD_POOL).getReward(address(this), true); // claimExtraRewards = true
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL).getReward(address(this));
            return true;
        }
        return false;
    }

    function claimRewardTokens() 
        external onlyRole(REWARD_REINVESTMENT_ROLE) returns (        
            IERC20[] memory rewardTokens,
            uint256[] memory claimedBalances
        ) {
        rewardTokens = _rewardTokens();
        claimedBalances = RewardUtils._claimRewardTokens(_claimConvexRewardTokens, rewardTokens);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
