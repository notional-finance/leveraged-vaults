// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    VeBalDelegatorInfo,
    RewardTokenTradeParams,
    ReinvestRewardParams,
    PoolContext,
    BoostContext,
    OracleContext
} from "./BalancerVaultTypes.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {ITradingModule, Trade} from "../../../interfaces/trading/ITradingModule.sol";
import {IVeBalDelegator} from "../../../interfaces/notional/IVeBalDelegator.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";

library RewardHelper {
    using TradeHandler for Trade;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    error InvalidRewardToken(address token);
    error InvalidMaxAmounts(uint256 pairPrice, uint256 maxPrimary, uint256 maxSecondary);

    function _isValidRewardToken(
        VeBalDelegatorInfo memory info,
        address token
    ) private view returns (bool) {
        if (token == info.balToken) return true;
        else {
            if (address(info.liquidityGauge) != address(0)) {
                address[] memory rewardTokens = info.veBalDelegator
                    .getGaugeRewardTokens(address(info.liquidityGauge));
                for (uint256 i; i < rewardTokens.length; i++) {
                    if (rewardTokens[i] == token) return true;
                }
            }
            return false;
        }
    }

    function _validateTrades(
        VeBalDelegatorInfo memory info,
        ITradingModule tradingModule,
        Trade memory primaryTrade,
        Trade memory secondaryTrade,
        address primaryToken,
        address secondaryToken
    ) private view {
        // Validate trades
        if (
            !_isValidRewardToken(
                info,
                primaryTrade.sellToken
            )
        ) {
            revert InvalidRewardToken(primaryTrade.sellToken);
        }
        if (primaryTrade.sellToken != secondaryTrade.sellToken) {
            revert InvalidRewardToken(secondaryTrade.sellToken);
        }
        if (primaryTrade.buyToken != BalancerUtils.getTokenAddress(primaryToken)) {
            revert InvalidRewardToken(primaryTrade.buyToken);
        }
        if (
            secondaryTrade.buyToken !=
            BalancerUtils.getTokenAddress(secondaryToken)
        ) {
            revert InvalidRewardToken(secondaryTrade.buyToken);
        }

        primaryTrade._validateSlippage(tradingModule, Constants.REWARD_TRADE_SLIPPAGE_PERCENT);
        secondaryTrade._validateSlippage(tradingModule, Constants.REWARD_TRADE_SLIPPAGE_PERCENT);
    }

    function _executeRewardTrades(
        VeBalDelegatorInfo memory info,
        ITradingModule tradingModule,
        address primaryToken,
        address secondaryToken,
        bytes memory data
    ) private returns (uint256 primaryAmount, uint256 secondaryAmount) {
        RewardTokenTradeParams memory params = abi.decode(
            data,
            (RewardTokenTradeParams)
        );

        _validateTrades(
            info,
            tradingModule,
            params.primaryTrade,
            params.secondaryTrade,
            primaryToken,
            secondaryToken
        );

        uint256 primaryAmountBefore = TokenUtils.tokenBalance(primaryToken);
        // @audit this needs to be a delegate call
        tradingModule.executeTrade(params.primaryTradeDexId, params.primaryTrade);
        primaryAmount =
            TokenUtils.tokenBalance(primaryToken) -
            primaryAmountBefore;

        uint256 secondaryAmountBefore = TokenUtils.tokenBalance(secondaryToken);
        // @audit this needs to be a delegate call
        tradingModule.executeTrade(params.secondaryTradeDexId, params.secondaryTrade);
        secondaryAmount =
            TokenUtils.tokenBalance(secondaryToken) -
            secondaryAmountBefore;
    }

    function claimRewardTokens(BoostContext memory context) external {
        // @audit perhaps it would be more efficient to then call executeRewardTrades right after
        // this claim is done inside the same method?
        // @audit part of this BAL that is claimed needs to be donated to the Notional protocol,
        // we should set an percentage and then transfer to the TreasuryManager contract.
        context.boostController.claimBAL(context.liquidityGauge);

        // @audit perhaps it would be more efficient to then call executeRewardTrades right after
        // this claim is done inside the same method?
        context.boostController.claimGaugeTokens(context.liquidityGauge);
    }

    function _validateJoinAmounts(
        PoolContext memory poolContext,
        OracleContext memory oracleContext, 
        ITradingModule tradingModule,
        uint256 primaryAmount, 
        uint256 secondaryAmount
    ) private view {
        (uint256 normalizedPrimary, uint256 normalizedSecondary) = BalancerUtils._normalizeBalances(
            primaryAmount, oracleContext.primaryDecimals, secondaryAmount, oracleContext.secondaryDecimals
        );
        (
            int256 answer, int256 decimals
        ) = tradingModule.getOraclePrice(poolContext.primaryToken, poolContext.secondaryToken);

        require(decimals == BalancerUtils.BALANCER_PRECISION.toInt());

        uint256 calculatedPairPrice = normalizedSecondary * BalancerUtils.BALANCER_PRECISION / 
            normalizedPrimary;

        uint256 pairPrice = answer.toUint();
        uint256 lowerLimit = (pairPrice * Constants.MAX_JOIN_AMOUNTS_LOWER_LIMIT) / 100;
        uint256 upperLimit = (pairPrice * Constants.MAX_JOIN_AMOUNTS_UPPER_LIMIT) / 100;
        if (calculatedPairPrice < lowerLimit || upperLimit < calculatedPairPrice) {
            revert InvalidMaxAmounts(pairPrice, primaryAmount, secondaryAmount);
        }
    }

    function reinvestReward(
        ReinvestRewardParams memory params,
        VeBalDelegatorInfo memory info,
        ITradingModule tradingModule,
        PoolContext memory poolContext,
        OracleContext memory oracleContext
    ) external {
        (uint256 primaryAmount, uint256 secondaryAmount) = _executeRewardTrades(
            info,
            tradingModule,
            poolContext.primaryToken,
            poolContext.secondaryToken,
            params.tradeData
        );

        // Make sure we are joining with the right proportion to minimize slippage
        _validateJoinAmounts(poolContext, oracleContext, tradingModule, primaryAmount, secondaryAmount);

        BalancerUtils.joinPoolExactTokensIn(
            poolContext,
            primaryAmount,
            secondaryAmount,
            params.minBPT
        );

        // TODO: emit event here
    }
}
