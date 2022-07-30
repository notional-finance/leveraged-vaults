// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    RewardTokenTradeParams,
    ReinvestRewardParams,
    PoolContext,
    WeightedOracleContext,
    AuraStakingContext,
    TwoTokenPoolContext
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {SafeInt256} from "../../../global/SafeInt256.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";
import {TradeHandler} from "../../../trading/TradeHandler.sol";
import {ITradingModule, Trade} from "../../../../interfaces/trading/ITradingModule.sol";
import {ILiquidityGauge} from "../../../../interfaces/balancer/ILiquidityGauge.sol";
import {nProxy} from "../../../proxy/nProxy.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";

library RewardHelper {
    using TokenUtils for IERC20;
    using TradeHandler for Trade;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    error InvalidRewardToken(address token);
    error InvalidMaxAmounts(uint256 oraclePrice, uint256 maxPrimary, uint256 maxSecondary);
    error InvalidSpotPrice(uint256 oraclePrice, uint256 spotPrice);

    event RewardReinvested(address token, uint256 primaryAmount, uint256 secondaryAmount, uint256 bptAmount);

    function _isValidRewardToken(AuraStakingContext memory context, address token)
        private pure returns (bool) {
        for (uint256 i; i < context.rewardTokens.length; i++) {
            if (address(context.rewardTokens[i]) == token) return true;
        }
        return false;
    }

    function _validateTrades(
        AuraStakingContext memory context,
        Trade memory primaryTrade,
        Trade memory secondaryTrade,
        address primaryToken,
        address secondaryToken
    ) private pure {
        // Validate trades
        if (!_isValidRewardToken(context, primaryTrade.sellToken)) {
            revert InvalidRewardToken(primaryTrade.sellToken);
        }
        if (primaryTrade.sellToken != secondaryTrade.sellToken) {
            revert InvalidRewardToken(secondaryTrade.sellToken);
        }
        if (primaryTrade.buyToken != primaryToken) {
            revert InvalidRewardToken(primaryTrade.buyToken);
        }
        if (secondaryTrade.buyToken != secondaryToken) {
            revert InvalidRewardToken(secondaryTrade.buyToken);
        }
    }

    function _executeRewardTrades(
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        bytes memory data
    ) private returns (address rewardToken, uint256 primaryAmount, uint256 secondaryAmount) {
        RewardTokenTradeParams memory params = abi.decode(
            data,
            (RewardTokenTradeParams)
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

    function _executeTradeWithDynamicSlippage(
        uint16 dexId,
        Trade memory trade,
        ITradingModule tradingModule,
        uint32 dynamicSlippageLimit
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(tradingModule))).getImplementation()
            .delegatecall(abi.encodeWithSelector(
                ITradingModule.executeTradeWithDynamicSlippage.selector,
                dexId, trade, dynamicSlippageLimit
            )
        );
        require(success);
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    function _validateJoinAmounts(
        TwoTokenPoolContext memory context,
        uint256 spotPrice,
        ITradingModule tradingModule,
        uint256 primaryAmount, 
        uint256 secondaryAmount
    ) private view {
        (uint256 normalizedPrimary, uint256 normalizedSecondary) = BalancerUtils._normalizeBalances(
            primaryAmount, context.primaryDecimals, secondaryAmount, context.secondaryDecimals
        );
        (
            int256 answer, int256 decimals
        ) = tradingModule.getOraclePrice(context.secondaryToken, context.primaryToken);

        require(decimals == BalancerUtils.BALANCER_PRECISION.toInt());

        uint256 oraclePrice = answer.toUint();
        uint256 lowerLimit = (oraclePrice * Constants.MAX_JOIN_AMOUNTS_LOWER_LIMIT) / 100;
        uint256 upperLimit = (oraclePrice * Constants.MAX_JOIN_AMOUNTS_UPPER_LIMIT) / 100;

        // Check spot price against oracle price to make sure it hasn't been manipulated
        if (spotPrice < lowerLimit || upperLimit < spotPrice) {
            revert InvalidSpotPrice(oraclePrice, spotPrice);
        }

        // Check join amounts against oracle price to minimize BPT slippage
        uint256 calculatedPairPrice = normalizedPrimary * BalancerUtils.BALANCER_PRECISION / 
            normalizedSecondary;
        if (calculatedPairPrice < lowerLimit || upperLimit < calculatedPairPrice) {
            revert InvalidMaxAmounts(oraclePrice, primaryAmount, secondaryAmount);
        }
    }

    function _reinvestReward(
        ReinvestRewardParams memory params,
        ITradingModule tradingModule,
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        uint256 spotPrice
    ) internal {
        (address rewardToken, uint256 primaryAmount, uint256 secondaryAmount) = _executeRewardTrades(
            poolContext,
            stakingContext,
            tradingModule,
            params.tradeData
        );

        // Make sure we are joining with the right proportion to minimize slippage
        _validateJoinAmounts(poolContext, spotPrice, tradingModule, primaryAmount, secondaryAmount);
        
        uint256 bptAmount = BalancerUtils.joinPoolExactTokensIn({
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

        emit RewardReinvested(rewardToken, primaryAmount, secondaryAmount, bptAmount); 
    }
}
