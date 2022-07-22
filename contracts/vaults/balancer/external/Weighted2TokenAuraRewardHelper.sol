// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    Weighted2TokenAuraStrategyContext
} from "../BalancerVaultTypes.sol";
import {RewardHelper} from "../internal/RewardHelper.sol";
import {BalancerUtils} from "../BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Weighted2TokenOracleMath} from "../internal/Weighted2TokenOracleMath.sol";

library Weighted2TokenAuraRewardHelper {
    function reinvestReward(
        ReinvestRewardParams memory params,
        ITradingModule tradingModule,
        Weighted2TokenAuraStrategyContext memory context
    ) external {
        RewardHelper._reinvestReward(
            params, 
            tradingModule, 
            context.poolContext,
            context.stakingContext,
            Weighted2TokenOracleMath.getSpotPrice(context.oracleContext, context.poolContext, 0)
        );
    }
}