// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/WETH9.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/trading/ITradingModule.sol";

library TradeHandler {
    using SafeERC20 for IERC20;

    address public constant ETH_ADDRESS = address(0);

    event TradeExecuted(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    );

    function _preValidate(Trade memory trade, uint256 preTradeBalance)
        internal
        view
    {
        if (_isExactIn(trade)) {
            require(preTradeBalance >= trade.amount, "preValidate amount");
        } else if (_isExactOut(trade)) {
            require(preTradeBalance >= trade.limit, "preValidate amount");
        } else {
            revert("preValidate type");
        }
    }

    function _postValidate(Trade memory trade, uint256 amountReceived)
        internal
        view
    {
        if (_isExactIn(trade)) {
            require(amountReceived >= trade.limit, "postValidate amount");
        } else if (_isExactOut(trade)) {
            require(amountReceived == trade.amount, "postValidate amount");
        }
    }

    /// @notice Approve exchange to pull from this contract
    /// @dev approve up to trade.amount for EXACT_IN trades and up to trade.limit
    /// for EXACT_OUT trades
    function _approve(Trade memory trade, address spender) internal {
        if (_isExactIn(trade)) {
            IERC20(trade.sellToken).safeApprove(spender, 0);
            IERC20(trade.sellToken).safeApprove(spender, trade.amount);
        } else if (_isExactOut(trade)) {
            IERC20(trade.sellToken).safeApprove(spender, 0);
            IERC20(trade.sellToken).safeApprove(spender, trade.limit);
        }
    }

    /// @notice Revoke exchange approvals
    function _revoke(Trade memory trade, address spender) internal {
        IERC20(trade.sellToken).safeApprove(spender, 0);
    }

    function _executeInternal(
        Trade memory trade,
        ITradingModule tradingModule,
        uint16 dexId
    ) private {
        // prettier-ignore
        (
            address target, 
            uint256 value, 
            bytes memory params
        ) = tradingModule.getExecutionData(dexId, payable(address(this)), trade);

        (bool success, ) = target.call{value: value}(params);
        require(success);
    }

    function _execute(
        Trade memory trade,
        ITradingModule tradingModule,
        uint16 dexId,
        WETH9 weth
    ) external returns (uint256 amountSold, uint256 amountBought) {
        require(trade.buyToken != trade.sellToken, "same token");

        // Get pre-trade token balances
        // prettier-ignore
        (
            uint256 preTradeSellBalance,
            uint256 preTradeBuyBalance
        ) = _getBalances(trade);

        // Make sure we have enough tokens to sell
        _preValidate(trade, preTradeSellBalance);

        // Get approval target based on the current trade
        address spender = tradingModule.getSpender(dexId, trade);

        // No need to approve ETH trades
        if (spender != ETH_ADDRESS && DexId(dexId) != DexId.NOTIONAL_VAULT) {
            // Approve exchange
            _approve(trade, spender);
        }

        uint256 preTradeETHBalance = address(this).balance;

        // Some exchanges don't support WETH (spender == address(0))
        if (trade.sellToken == address(weth) && spender == ETH_ADDRESS) {
            if (_isExactIn(trade)) {
                weth.withdraw(trade.amount);
            } else if (_isExactOut(trade)) {
                weth.withdraw(trade.limit);
            }
        }

        // Avoids stack too deep
        _executeInternal(trade, tradingModule, dexId);

        uint256 postTradeETHBalance = address(this).balance;

        // Wrap into WETH if we received ETH from this trade
        if (
            trade.buyToken == address(weth) &&
            postTradeETHBalance > preTradeETHBalance
        ) {
            weth.deposit{value: postTradeETHBalance - preTradeETHBalance}();
        }

        // Get post-trade token balances
        // prettier-ignore
        (
            uint256 postTradeSellBalance,
            uint256 postTradeBuyBalance
        ) = _getBalances(trade);

        _postValidate(trade, postTradeBuyBalance - preTradeBuyBalance);

        // No need to revoke ETH trades
        if (spender != ETH_ADDRESS && DexId(dexId) != DexId.NOTIONAL_VAULT) {
            _revoke(trade, spender);
        }

        amountSold = preTradeSellBalance - postTradeSellBalance;
        amountBought = postTradeBuyBalance - preTradeBuyBalance;

        emit TradeExecuted(
            trade.sellToken,
            trade.buyToken,
            amountSold,
            amountBought
        );
    }

    function _getBalances(Trade memory trade)
        private
        view
        returns (uint256, uint256)
    {
        return (
            trade.sellToken == ETH_ADDRESS
                ? address(this).balance
                : IERC20(trade.sellToken).balanceOf(address(this)),
            trade.buyToken == ETH_ADDRESS
                ? address(this).balance
                : IERC20(trade.buyToken).balanceOf(address(this))
        );
    }

    function _isExactIn(Trade memory trade) private pure returns (bool) {
        return
            TradeType(trade.tradeType) == TradeType.EXACT_IN_SINGLE ||
            TradeType(trade.tradeType) == TradeType.EXACT_IN_BATCH;
    }

    function _isExactOut(Trade memory trade) private pure returns (bool) {
        return
            TradeType(trade.tradeType) == TradeType.EXACT_OUT_SINGLE ||
            TradeType(trade.tradeType) == TradeType.EXACT_OUT_BATCH;
    }
}
