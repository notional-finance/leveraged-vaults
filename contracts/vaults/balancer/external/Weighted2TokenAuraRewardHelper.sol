// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    Weighted2TokenAuraStrategyContext,
    WeightedOracleContext,
    TwoTokenPoolContext
} from "../BalancerVaultTypes.sol";
import {TwoTokenAuraRewardUtils} from "../internal/reward/TwoTokenAuraRewardUtils.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Weighted2TokenOracleMath} from "../internal/math/Weighted2TokenOracleMath.sol";

library Weighted2TokenAuraRewardHelper {
    using Weighted2TokenOracleMath for WeightedOracleContext;
    using TwoTokenAuraRewardUtils for TwoTokenPoolContext;

    function reinvestReward(
        Weighted2TokenAuraStrategyContext memory context,
        ReinvestRewardParams memory params
    ) external {
        (
            address rewardToken, 
            uint256 primaryAmount, 
            uint256 secondaryAmount
        ) = context.poolContext._executeRewardTrades(
            context.stakingContext,
            context.baseStrategy.tradingModule,
            params.tradeData
        );

        // Make sure we are joining with the right proportion to minimize slippage
        context.oracleContext._validateSpotPriceAndPairPrice({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            spotPrice: context.oracleContext._getSpotPrice(context.poolContext, 0),
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });

        context.poolContext._reinvestReward({
            stakingContext: context.stakingContext, 
            params: params,
            rewardToken: rewardToken,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });
    }
}