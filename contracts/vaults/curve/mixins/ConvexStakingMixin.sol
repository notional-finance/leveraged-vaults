// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ConvexStakingContext, ConvexVaultDeploymentParams, Curve2TokenConvexStrategyContext} from "../CurveVaultTypes.sol";
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
import {Curve2TokenPoolMixin} from "./Curve2TokenPoolMixin.sol";

abstract contract ConvexStakingMixin is Curve2TokenPoolMixin {
    using TokenUtils for IERC20;

    /// @notice Convex booster contract used for staking BPT
    address internal immutable CONVEX_BOOSTER;
    /// @notice Convex reward pool contract used for unstaking and claiming reward tokens
    address internal immutable CONVEX_REWARD_POOL;
    uint256 internal immutable CONVEX_POOL_ID;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        Curve2TokenPoolMixin(notional_, params) {
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
        if (TOKEN_1 != Deployments.ALT_ETH_ADDRESS) {
            IERC20(TOKEN_1).checkApprove(address(CURVE_POOL), type(uint256).max);
        }
        if (TOKEN_2 != Deployments.ALT_ETH_ADDRESS) {
            IERC20(TOKEN_2).checkApprove(address(CURVE_POOL), type(uint256).max);
        }

        CURVE_POOL_TOKEN.checkApprove(address(CONVEX_BOOSTER), type(uint256).max);
    }

    function _convexStakingContext() internal view returns (ConvexStakingContext memory) {
        return ConvexStakingContext({
            booster: CONVEX_BOOSTER,
            rewardPool: CONVEX_REWARD_POOL,
            poolId: CONVEX_POOL_ID
        });
    }

    function _strategyContext() internal view returns (Curve2TokenConvexStrategyContext memory) {
        return Curve2TokenConvexStrategyContext({
            baseStrategy: _baseStrategyContext(),
            poolContext: _twoTokenPoolContext(),
            stakingContext: _convexStakingContext()
        });
    }

    function getExchangeRate(uint256 /* maturity */) public view override returns (int256) {
        // Curve2TokenConvexStrategyContext memory context = _strategyContext();
        // if (context.baseStrategy.vaultState.totalVaultSharesGlobal == 0) {
        //     (uint256 spotPrice, uint256 oraclePrice) = context.poolContext._getSpotPriceAndOraclePrice(
        //         context.baseStrategy
        //     );

        //     return context.poolContext.basePool._getTimeWeightedPrimaryBalance({
        //         strategyContext: context.baseStrategy,
        //         poolClaim: context.baseStrategy.poolClaimPrecision, // 1 pool token
        //         oraclePrice: oraclePrice, 
        //         spotPrice: spotPrice
        //     }).toInt();
        // } else {
        //     return context.poolContext._convertStrategyToUnderlying({
        //         strategyContext: context.baseStrategy,
        //         vaultShareAmount: uint256(Constants.INTERNAL_TOKEN_PRECISION) // 1 vault share
        //     });
        // }
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

    function _claimRewardTokens() internal override {
        bool success = _claimConvexRewardTokens();
        require(success);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
