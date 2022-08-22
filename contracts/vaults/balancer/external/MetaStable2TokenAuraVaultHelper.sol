// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams,
    TwoTokenPoolContext,
    StrategyContext,
    StableOracleContext
} from "../BalancerVaultTypes.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/strategy/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenAuraRewardUtils} from "../internal/reward/TwoTokenAuraRewardUtils.sol";
import {Stable2TokenOracleMath} from "../internal/math/Stable2TokenOracleMath.sol";

library MetaStable2TokenAuraVaultHelper {
    using TwoTokenAuraRewardUtils for TwoTokenPoolContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Stable2TokenOracleMath for StableOracleContext;

    function reinvestReward(
        MetaStable2TokenAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
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
