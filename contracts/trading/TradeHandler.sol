// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;


import "../global/Constants.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/trading/ITradingModule.sol";
import {nProxy} from "../proxy/nProxy.sol";

/// @notice TradeHandler is an internal library to be compiled into StrategyVaults to interact
/// with the TradeModule and execute trades
library TradeHandler {
    using TradeHandler for Trade;
    using TokenUtils for IERC20;

    error ERC20Error();
    error TradeExecution(bytes returnData);
    error PreValidationExactIn(uint256 maxAmountIn, uint256 preTradeSellBalance);
    error PreValidationExactOut(uint256 maxAmountIn, uint256 preTradeSellBalance);
    error PostValidationExactIn(uint256 minAmountOut, uint256 amountReceived);
    error PostValidationExactOut(uint256 exactAmountOut, uint256 amountReceived);

    WETH9 public constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    event TradeExecuted(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    );

    function _executeInternal(
        Trade memory trade,
        uint16 dexId,
        address spender,
        address target,
        uint256 msgValue,
        bytes memory executionData
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        // Get pre-trade token balances
        (uint256 preTradeSellBalance, uint256 preTradeBuyBalance) = _getBalances(trade);

        // Make sure we have enough tokens to sell
        _preValidate(trade, preTradeSellBalance);

        // No need to approve ETH trades
        if (spender != Constants.ETH_ADDRESS && DexId(dexId) != DexId.NOTIONAL_VAULT) {
            _approve(trade, spender);
        }

        _executeTrade(target, msgValue, executionData, spender, trade);

        // Get post-trade token balances
        (uint256 postTradeSellBalance, uint256 postTradeBuyBalance) = _getBalances(trade);

        _postValidate(trade, postTradeBuyBalance - preTradeBuyBalance);

        // No need to revoke ETH trades
        if (spender != Constants.ETH_ADDRESS && DexId(dexId) != DexId.NOTIONAL_VAULT) {
            IERC20(trade.sellToken).checkRevoke(spender);
        }

        amountSold = preTradeSellBalance - postTradeSellBalance;
        amountBought = postTradeBuyBalance - preTradeBuyBalance;

        emit TradeExecuted(trade.sellToken, trade.buyToken, amountSold, amountBought);
    }

    function _getBalances(Trade memory trade) private view returns (uint256, uint256) {
        return (
            trade.sellToken == Constants.ETH_ADDRESS
                ? address(this).balance
                : IERC20(trade.sellToken).balanceOf(address(this)),
            trade.buyToken == Constants.ETH_ADDRESS
                ? address(this).balance
                : IERC20(trade.buyToken).balanceOf(address(this))
        );
    }

    function _isExactIn(Trade memory trade) private pure returns (bool) {
        return
            trade.tradeType == TradeType.EXACT_IN_SINGLE ||
            trade.tradeType == TradeType.EXACT_IN_BATCH;
    }

    function _isExactOut(Trade memory trade) private pure returns (bool) {
        return
            trade.tradeType == TradeType.EXACT_OUT_SINGLE ||
            trade.tradeType == TradeType.EXACT_OUT_BATCH;
    }

    function _preValidate(Trade memory trade, uint256 preTradeSellBalance) private pure {
        if (_isExactIn(trade) && preTradeSellBalance < trade.amount) {
            revert PreValidationExactIn(trade.amount, preTradeSellBalance);
        } 
        
        if (_isExactOut(trade) && preTradeSellBalance < trade.limit) {
            // NOTE: this implies that vaults cannot execute market trades on exact out
            revert PreValidationExactOut(trade.limit, preTradeSellBalance);
        }
    }

    function _postValidate(Trade memory trade, uint256 amountReceived) private pure {
        if (_isExactIn(trade) && amountReceived < trade.limit) {
            revert PostValidationExactIn(trade.limit, amountReceived);
        }

        if (_isExactOut(trade) && amountReceived != trade.amount) {
            revert PostValidationExactOut(trade.amount, amountReceived);
        }
    }

    /// @notice Approve exchange to pull from this contract
    /// @dev approve up to trade.amount for EXACT_IN trades and up to trade.limit
    /// for EXACT_OUT trades
    function _approve(Trade memory trade, address spender) private {
        uint256 allowance = _isExactIn(trade) ? trade.amount : trade.limit;
        IERC20(trade.sellToken).checkApprove(spender, allowance);
    }

    function _executeTrade(
        address target,
        uint256 msgValue,
        bytes memory params,
        address spender,
        Trade memory trade
    ) private {
        uint256 preTradeETHBalance = address(this).balance;
        uint256 preTradeWETHBalance = IERC20(address(WETH)).balanceOf(address(this));

        if (trade.sellToken == address(WETH) && spender == Constants.ETH_ADDRESS) {
            // Curve doesn't support WETH (spender == address(0))
            uint256 withdrawAmount = _isExactIn(trade) ? trade.amount : trade.limit;
            WETH.withdraw(withdrawAmount);
        } else if (trade.sellToken == Constants.ETH_ADDRESS && spender != Constants.ETH_ADDRESS) {
            // UniswapV3 doesn't support ETH (spender != address(0))
            uint256 depositAmount = _isExactIn(trade) ? trade.amount : trade.limit;
            WETH.deposit{value: depositAmount }();
        }

        (bool success, bytes memory returnData) = target.call{value: msgValue}(params);
        if (!success) revert TradeExecution(returnData);

        uint256 postTradeETHBalance = address(this).balance;
        uint256 postTradeWETHBalance = IERC20(address(WETH)).balanceOf(address(this));

        if (trade.buyToken == address(WETH) && postTradeETHBalance > preTradeETHBalance) {
            // If the caller specifies that they want to receive WETH but we have received ETH,
            // wrap the ETH to WETH.
            uint256 depositAmount;
            unchecked { depositAmount = postTradeETHBalance - preTradeETHBalance; }
            WETH.deposit{value: depositAmount}();
        } else if (trade.buyToken == Constants.ETH_ADDRESS && postTradeWETHBalance > preTradeWETHBalance) {
            // If the caller specifies that they want to receive ETH but we have received WETH,
            // unwrap the WETH to ETH.
            uint256 withdrawAmount;
            unchecked { withdrawAmount = postTradeWETHBalance - preTradeWETHBalance; }
            WETH.withdraw(withdrawAmount);
        }
    }

    /// @notice Can be used to delegate call to the TradingModule's implementation in order to execute
    /// a trade.
    function _executeTradeWithDynamicSlippage(
        Trade memory trade,
        uint16 dexId,
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

    function _executeTradeWithStaticSlippage(
        Trade memory trade,
        uint16 dexId,
        ITradingModule tradingModule
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(tradingModule))).getImplementation()
            .delegatecall(abi.encodeWithSelector(ITradingModule.executeTrade.selector, dexId, trade)
        );
        require(success);
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }
}
