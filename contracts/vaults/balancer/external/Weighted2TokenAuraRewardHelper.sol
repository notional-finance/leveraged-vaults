// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ReinvestRewardParams, Weighted2TokenAuraStrategyContext} from "../BalancerVaultTypes.sol";
import {RewardHelper} from "../RewardHelper.sol";
import {BalancerUtils} from "../BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";

library Weighted2TokenAuraRewardHelper {

    function reinvestReward(
        ReinvestRewardParams memory params,
        ITradingModule tradingModule,
        Weighted2TokenAuraStrategyContext memory context
    ) external {
        RewardHelper.reinvestReward(
            params, 
            tradingModule, 
            context.poolContext,
            context.stakingContext,
            BalancerUtils.getSpotPrice(context.oracleContext, context.poolContext, 0)
        );
    }
}