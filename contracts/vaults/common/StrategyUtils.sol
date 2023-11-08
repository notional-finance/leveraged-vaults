// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../interfaces/IERC20.sol";
import {TradeParams} from "./VaultTypes.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {Constants} from "../../global/Constants.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";

library StrategyUtils {
    using TradeHandler for Trade;

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
            0,
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
        /// @dev this function can only handle exact in trades
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE ||
            params.tradeType == TradeType.EXACT_IN_BATCH
        );

        // Sell residual secondary balance
        Trade memory trade = Trade(
            params.tradeType,
            sellToken,
            buyToken,
            amount,
            params.oracleSlippagePercentOrLimit,
            block.timestamp, // deadline
            params.exchangeData
        );

        // Execute trade using static slippage
        (amountSold, amountBought) = trade._executeTrade(params.dexId, tradingModule);
    }
}
