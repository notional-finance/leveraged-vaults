// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;

import {BalancerUtils} from "./BalancerUtils.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {ITradingModule, Trade} from "../../../interfaces/trading/ITradingModule.sol";
import {IVeBalDelegator} from "../../../interfaces/notional/IVeBalDelegator.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";

library RewardHelper {
    using TradeHandler for Trade;

    error InvalidRewardToken(address token);

    struct RewardTokenTradeParams {
        uint16 primaryTradeDexId;
        Trade primaryTrade;
        uint16 secondaryTradeDexId;
        Trade secondaryTrade;
    }

    struct ReinvestRewardParams {
        bytes tradeData;
        uint256 minBPT;
    }

    struct VeBalDelegatorInfo {
        IVeBalDelegator veBalDelegator;
        ILiquidityGauge liquidityGauge;
        address balToken;
    }

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
        if (primaryTrade.buyToken != BalancerUtils.tokenAddress(primaryToken)) {
            revert InvalidRewardToken(primaryTrade.buyToken);
        }
        if (
            secondaryTrade.buyToken !=
            BalancerUtils.tokenAddress(secondaryToken)
        ) {
            revert InvalidRewardToken(secondaryTrade.buyToken);
        }

        // TODO: validate prices
        // TODO: make sure spot is close to pairPrice
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
            params.primaryTrade,
            params.secondaryTrade,
            primaryToken,
            secondaryToken
        );

        uint256 primaryAmountBefore = TokenUtils.tokenBalance(primaryToken);
        params.primaryTrade.execute(tradingModule, params.primaryTradeDexId);
        primaryAmount =
            TokenUtils.tokenBalance(primaryToken) -
            primaryAmountBefore;

        uint256 secondaryAmountBefore = TokenUtils.tokenBalance(secondaryToken);
        params.secondaryTrade.execute(
            tradingModule,
            params.secondaryTradeDexId
        );
        secondaryAmount =
            TokenUtils.tokenBalance(secondaryToken) -
            secondaryAmountBefore;
    }

    function reinvestReward(
        ReinvestRewardParams memory params,
        VeBalDelegatorInfo memory info,
        ITradingModule tradingModule,
        bytes32 poolId,
        address primaryToken,
        address secondaryToken,
        uint8 primaryIndex
    ) external {
        (uint256 primaryAmount, uint256 secondaryAmount) = _executeRewardTrades(
            info,
            tradingModule,
            primaryToken,
            secondaryToken,
            params.tradeData
        );

        BalancerUtils.joinPoolExactTokensIn(
            poolId,
            primaryToken,
            primaryAmount,
            secondaryToken,
            secondaryAmount,
            primaryIndex,
            params.minBPT
        );

        // TODO: emit event here
    }
}
