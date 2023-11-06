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
import {VaultStorage} from "../../common/VaultStorage.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {SingleSidedLPVaultBase} from "../../common/SingleSidedLPVaultBase.sol";

abstract contract ConvexStakingMixin is SingleSidedLPVaultBase {
    using TokenUtils for IERC20;

    /// @notice Convex booster contract used for staking BPT
    address internal immutable CONVEX_BOOSTER;
    /// @notice Convex reward pool contract used for unstaking and claiming reward tokens
    address internal immutable CONVEX_REWARD_POOL;
    uint256 internal immutable CONVEX_POOL_ID;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        SingleSidedLPVaultBase(notional_, params.baseParams.tradingModule) {
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

    function _convexStakingContext() internal view returns (ConvexStakingContext memory) {
        return ConvexStakingContext({
            booster: CONVEX_BOOSTER,
            rewardPool: CONVEX_REWARD_POOL,
            poolId: CONVEX_POOL_ID
        });
    }

    function _claimConvexRewardTokens() private returns (bool) {
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            return IConvexRewardPool(CONVEX_REWARD_POOL).getReward(address(this), true); // claimExtraRewards = true
        } else if (Deployments.CHAIN_ID == Constants.CHAIN_ID_ARBITRUM) {
            IConvexRewardPoolArbitrum(CONVEX_REWARD_POOL).getReward(address(this));
            return true;
        }
        return false;
    }

    function claimRewardTokens() external onlyRole(REWARD_REINVESTMENT_ROLE) {
        bool success = _claimConvexRewardTokens();
        require(success);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
