// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    Balanced2TokenRewardTradeParams,
    SingleSidedRewardTradeParams,
    ReinvestRewardParams,
    PoolContext,
    WeightedOracleContext,
    AuraStakingContext,
    TwoTokenPoolContext
} from "../../BalancerVaultTypes.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Events} from "../../../../global/Events.sol";
import {Constants} from "../../../../global/Constants.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";
import {TwoTokenPoolUtils} from "../pool/TwoTokenPoolUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";

library TwoTokenAuraRewardUtils {
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;

    function _validateTrades(
        AuraStakingContext memory context,
        SingleSidedRewardTradeParams memory primaryTrade,
        SingleSidedRewardTradeParams memory secondaryTrade,
        address primaryToken,
        address secondaryToken
    ) private pure {
        // Validate trades
        if (!context._isValidRewardToken(primaryTrade.sellToken)) {
            revert Errors.InvalidRewardToken(primaryTrade.sellToken);
        }
        if (secondaryTrade.sellToken != primaryTrade.sellToken) {
            revert Errors.InvalidRewardToken(secondaryTrade.sellToken);
        }
        if (primaryTrade.buyToken != primaryToken) {
            revert Errors.InvalidRewardToken(primaryTrade.buyToken);
        }
        if (secondaryTrade.buyToken != secondaryToken) {
            revert Errors.InvalidRewardToken(secondaryTrade.buyToken);
        }

        // TODO: maybe make MAX_REWARD_TRADE_SLIPPAGE_PERCENT configurable?
        require(primaryTrade.tradeParams.oracleSlippagePercent <= Constants.MAX_REWARD_TRADE_SLIPPAGE_PERCENT);
        require(secondaryTrade.tradeParams.oracleSlippagePercent <= Constants.MAX_REWARD_TRADE_SLIPPAGE_PERCENT);
    }

    function _executeRewardTrades(
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        bytes memory data
    ) internal returns (address rewardToken, uint256 primaryAmount, uint256 secondaryAmount) {
        Balanced2TokenRewardTradeParams memory params = abi.decode(
            data,
            (Balanced2TokenRewardTradeParams)
        );

        _validateTrades(
            stakingContext,
            params.primaryTrade,
            params.secondaryTrade,
            poolContext.primaryToken,
            poolContext.secondaryToken
        );

        (/*uint256 amountSold*/, primaryAmount) = StrategyUtils._executeDynamicTradeExactIn({
            params: params.primaryTrade.tradeParams,
            tradingModule: tradingModule,
            sellToken: params.primaryTrade.sellToken,
            buyToken: params.primaryTrade.buyToken,
            amount: params.primaryTrade.amount
        });

        (/*uint256 amountSold*/, secondaryAmount) = StrategyUtils._executeDynamicTradeExactIn({
            params: params.secondaryTrade.tradeParams,
            tradingModule: tradingModule,
            sellToken: params.secondaryTrade.sellToken,
            buyToken: params.secondaryTrade.buyToken,
            amount: params.secondaryTrade.amount
        });

        rewardToken = params.primaryTrade.sellToken;
    }

    function _reinvestReward(
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        ReinvestRewardParams memory params,
        address rewardToken,
        uint256 primaryAmount,
        uint256 secondaryAmount
    ) internal {        
        uint256 bptAmount = BalancerUtils._joinPoolExactTokensIn({
            context: poolContext.basePool,
            params: poolContext._getPoolParams(
                primaryAmount, 
                secondaryAmount, 
                true // isJoin
            ),
            minBPT: params.minBPT
        });

        stakingContext.auraBooster.deposit(
            stakingContext.auraPoolId, bptAmount, true // stake = true
        );

        emit Events.RewardReinvested(rewardToken, primaryAmount, secondaryAmount, bptAmount); 
    }
}
