// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    MetaStable2TokenAuraStrategyContext
} from "../BalancerVaultTypes.sol";
import {RewardHelper} from "../internal/RewardHelper.sol";
import {BalancerUtils} from "../BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Stable2TokenOracleMath} from "../internal/Stable2TokenOracleMath.sol";

library MetaStable2TokenAuraRewardHelper {
    function reinvestReward(
        ReinvestRewardParams memory params,
        ITradingModule tradingModule,
        MetaStable2TokenAuraStrategyContext memory context
    ) external {
        RewardHelper._reinvestReward(
            params, 
            tradingModule, 
            context.poolContext,
            context.stakingContext,
            Stable2TokenOracleMath.getSpotPrice(context.oracleContext, context.poolContext, 0)
        );
    }
}
