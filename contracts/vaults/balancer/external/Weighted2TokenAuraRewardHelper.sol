// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    Weighted2TokenAuraStrategyContext,
    WeightedOracleContext,
    TwoTokenPoolContext
} from "../BalancerVaultTypes.sol";
import {TwoTokenAuraRewardUtils} from "../internal/TwoTokenAuraRewardUtils.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Weighted2TokenOracleMath} from "../internal/Weighted2TokenOracleMath.sol";

library Weighted2TokenAuraRewardHelper {
    using Weighted2TokenOracleMath for WeightedOracleContext;
    using TwoTokenAuraRewardUtils for TwoTokenPoolContext;

    function reinvestReward(
        Weighted2TokenAuraStrategyContext memory context,
        ReinvestRewardParams memory params
    ) external {
        context.poolContext._reinvestReward({
            stakingContext: context.stakingContext,
            tradingModule: context.baseStrategy.tradingModule,
            params: params,
            spotPrice: context.oracleContext._getSpotPrice(context.poolContext, 0)
        });
    }
}