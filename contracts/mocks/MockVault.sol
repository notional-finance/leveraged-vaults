// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TradeHandler} from "../trading/TradeHandler.sol";
import {ITradingModule, Trade} from "../../interfaces/trading/ITradingModule.sol";

/// @notice MockVault used to test the trading module
contract MockVault {
    ITradingModule public immutable TRADING_MODULE;

    constructor(ITradingModule tradingModule_) {
        TRADING_MODULE = tradingModule_;
    }

    function executeTradeWithDynamicSlippage(
        uint16 dexId,
        Trade memory trade,
        uint32 dynamicSlippageLimit
    ) external returns (uint256 amountSold, uint256 amountBought) {
        return TradeHandler._executeTradeWithDynamicSlippage(trade, dexId, TRADING_MODULE, dynamicSlippageLimit);
    }

    function executeTrade(uint16 dexId, Trade memory trade) 
        external returns (uint256 amountSold, uint256 amountBought) {
        return TradeHandler._executeTrade(trade, dexId, TRADING_MODULE);
    }

    receive() external payable {}
}
