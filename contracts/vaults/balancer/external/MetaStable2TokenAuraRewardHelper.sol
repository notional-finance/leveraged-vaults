// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    MetaStable2TokenAuraStrategyContext,
    StableOracleContext
} from "../BalancerVaultTypes.sol";
import {RewardHelper} from "../internal/RewardHelper.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Stable2TokenOracleMath} from "../internal/Stable2TokenOracleMath.sol";

library MetaStable2TokenAuraRewardHelper {
    using Stable2TokenOracleMath for StableOracleContext;

    function reinvestReward(
        MetaStable2TokenAuraStrategyContext memory context,
        ITradingModule tradingModule,
        ReinvestRewardParams memory params
    ) external {
        RewardHelper._reinvestReward(
            params, 
            tradingModule, 
            context.poolContext,
            context.stakingContext,
            context.oracleContext._getSpotPrice(context.poolContext, 0)
        );
    }
}
