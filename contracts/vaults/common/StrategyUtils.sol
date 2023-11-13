// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../interfaces/IERC20.sol";
import {
    TradeParams,
    DepositTradeParams,
    RedeemParams,
    SingleSidedRewardTradeParams
} from "../../../interfaces/notional/ISingleSidedLPStrategyVault.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {Deployments} from "../../global/Deployments.sol";
import {Constants} from "../../global/Constants.sol";
import {Errors} from "../../global/Errors.sol";
import {ITradingModule, Trade, TradeType, DexId} from "../../../interfaces/trading/ITradingModule.sol";

/**
 * @notice External library deployed for the purposes of handling SingleSidedLP trades. All
 * the methods in this library are called inside a `delegateCall` context which ensures that
 * the library has access to the calling vault's token balances
 */
library StrategyUtils {
    using TradeHandler for Trade;

    /// @notice Trades the amount of primary token into other secondary tokens prior
    /// to entering a pool.
    function executeDepositTrades(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        DepositTradeParams[] memory depositTrades,
        uint256 primaryIndex
    ) external returns (uint256[] memory) {
        address primaryToken = address(tokens[primaryIndex]);

        for (uint256 i; i < amounts.length; i++) {
            if (i == primaryIndex) continue;
            DepositTradeParams memory t = depositTrades[i];
            // Do not allow ZERO_EX trading in this method since we cannot validate
            // the arbitrary exchange data.
            if (DexId(t.tradeParams.dexId) == DexId.ZERO_EX) revert Errors.InvalidDexId(uint256(DexId.ZERO_EX));

            if (t.tradeAmount > 0) {
                // Always selling the primaryToken and buying the secondary token.
                (uint256 amountSold, uint256 amountBought) = _executeDynamicSlippageTradeExactIn(
                    Deployments.TRADING_MODULE, t.tradeParams, primaryToken, address(tokens[i]), t.tradeAmount
                );

                amounts[i] = amountBought;
                // Will revert on underflow if over-selling the primary borrowed
                amounts[primaryIndex] -= amountSold;
            }
        }

        return amounts;
    }

    /// @notice Trades the amount of secondary tokens into the primary token after
    /// exiting a pool.
    function executeRedemptionTrades(
        IERC20[] memory tokens,
        uint256[] memory exitBalances,
        TradeParams[] memory redemptionTrades,
        uint256 primaryIndex
    ) external returns (uint256 finalPrimaryBalance) {
        address primaryToken = address(tokens[primaryIndex]);

        for (uint256 i; i < exitBalances.length; i++) {
            if (i == primaryIndex) {
                finalPrimaryBalance += exitBalances[i];
                continue;
            }

            TradeParams memory t = redemptionTrades[i];
            // Do not allow ZERO_EX trading in this method since we cannot validate
            // the arbitrary exchange data.
            if (DexId(t.dexId) == DexId.ZERO_EX) revert Errors.InvalidDexId(uint256(DexId.ZERO_EX));

            // Always sell the entire exit balance to the primary token
            if (exitBalances[i] > 0) {
                (/* */, uint256 amountBought) = _executeDynamicSlippageTradeExactIn(
                    Deployments.TRADING_MODULE, t, address(tokens[i]), primaryToken, exitBalances[i]
                );

                finalPrimaryBalance += amountBought;
            }
        }
    }

    /// @notice Executes a set of trades to sell the reward token for constituent pool tokens.
    function executeRewardTrades(
        IERC20[] memory tokens,
        SingleSidedRewardTradeParams[] calldata trades,
        address rewardToken,
        address poolToken
    ) external returns(uint256[] memory amounts, uint256 amountSold) {
        amounts = new uint256[](trades.length);
        for (uint256 i; i < trades.length; i++) {
            // All trades must sell the same token.
            require(trades[i].sellToken == rewardToken);
            // Bypass certain invalid trades
            if (trades[i].amount == 0) continue;
            if (trades[i].buyToken == poolToken) continue;

            // The reward trade can only purchase tokens that go into the pool
            require(trades[i].buyToken == address(tokens[i]));

            // It may be possible that the entire balance of reward tokens is not sold by the vault,
            // but that is ok.
            (uint256 sold, uint256 bought) = _executeTradeWithStaticSlippage(
                Deployments.TRADING_MODULE, trades[i].tradeParams, rewardToken, trades[i].buyToken, trades[i].amount
            );
            amounts[i] = bought;
            amountSold += sold;
        }
    }

    /// @notice Executes a trade that uses a dynamic slippage amount relative to the current
    /// oracle price.
    function _executeDynamicSlippageTradeExactIn(
        ITradingModule tradingModule,
        TradeParams memory params,
        address sellToken,
        address buyToken,
        uint256 amount
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        // Can only do exact in trades
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE ||
            params.tradeType == TradeType.EXACT_IN_BATCH
        );
        // Ensure that the slippage percent is valid
        require(params.oracleSlippagePercentOrLimit <= Constants.SLIPPAGE_LIMIT_PRECISION);

        Trade memory trade = Trade(
            params.tradeType,
            sellToken,
            buyToken,
            amount,
            0, // No absolute slippage limit is set here
            block.timestamp, // deadline
            params.exchangeData
        );

        (amountSold, amountBought) = trade._executeTradeWithDynamicSlippage(
            params.dexId, tradingModule, uint32(params.oracleSlippagePercentOrLimit)
        );
    }

    /// @notice Executes a trade with a static slippage limit, only used during
    /// reward reinvestment trades since oracles between the reward token and the
    /// purchased tokens may not exist.
    function _executeTradeWithStaticSlippage(
        ITradingModule tradingModule,
        TradeParams memory params,
        address sellToken,
        address buyToken,
        uint256 amount
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE ||
            params.tradeType == TradeType.EXACT_IN_BATCH
        );

        Trade memory trade = Trade(
            params.tradeType,
            sellToken,
            buyToken,
            amount,
            params.oracleSlippagePercentOrLimit,
            block.timestamp, // deadline
            params.exchangeData
        );

        // Execute trade using the absolute slippage limit set by `oracleSlippagePercentOrLimit`
        (amountSold, amountBought) = trade._executeTrade(params.dexId, tradingModule);
    }
}
