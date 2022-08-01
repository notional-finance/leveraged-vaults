// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    Balanced2TokenRewardTradeParams,
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
import {TradeHandler} from "../../../../trading/TradeHandler.sol";
import {ITradingModule, Trade} from "../../../../../interfaces/trading/ITradingModule.sol";
import {TwoTokenPoolUtils} from "../pool/TwoTokenPoolUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";

library TwoTokenAuraRewardUtils {
    using TradeHandler for Trade;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;

    function _validateTrades(
        AuraStakingContext memory context,
        Trade memory primaryTrade,
        Trade memory secondaryTrade,
        address primaryToken,
        address secondaryToken
    ) private pure {
        // Validate trades
        if (!context._isValidRewardToken(primaryTrade.sellToken)) {
            revert Errors.InvalidRewardToken(primaryTrade.sellToken);
        }
        if (primaryTrade.sellToken != secondaryTrade.sellToken) {
            revert Errors.InvalidRewardToken(secondaryTrade.sellToken);
        }
        if (primaryTrade.buyToken != primaryToken) {
            revert Errors.InvalidRewardToken(primaryTrade.buyToken);
        }
        if (secondaryTrade.buyToken != secondaryToken) {
            revert Errors.InvalidRewardToken(secondaryTrade.buyToken);
        }
    }

    function _executeRewardTrades(
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        bytes memory data
    ) private returns (address rewardToken, uint256 primaryAmount, uint256 secondaryAmount) {
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

        (/*uint256 amountSold*/, primaryAmount) = params.primaryTrade._executeTradeWithDynamicSlippage(
            params.primaryTradeDexId, tradingModule, Constants.REWARD_TRADE_SLIPPAGE_PERCENT
        );

        (/*uint256 amountSold*/, secondaryAmount) = params.secondaryTrade._executeTradeWithDynamicSlippage(
            params.secondaryTradeDexId, tradingModule, Constants.REWARD_TRADE_SLIPPAGE_PERCENT
        );

        rewardToken = params.primaryTrade.sellToken;
    }

    function _reinvestReward(
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        ReinvestRewardParams memory params,
        uint256 spotPrice
    ) internal {
        (address rewardToken, uint256 primaryAmount, uint256 secondaryAmount) = _executeRewardTrades(
            poolContext,
            stakingContext,
            tradingModule,
            params.tradeData
        );

        // Make sure we are joining with the right proportion to minimize slippage
        poolContext._validateJoinAmounts(spotPrice, tradingModule, primaryAmount, secondaryAmount);
        
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
