// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;


import "../global/Constants.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/trading/ITradingModule.sol";

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
    uint256 internal constant SLIPPAGE_LIMIT_PRECISION = 1e8;

    event TradeExecuted(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    );

    function execute(
        Trade memory trade,
        ITradingModule tradingModule,
        uint16 dexId
    ) external returns (uint256 amountSold, uint256 amountBought) {
        (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionData
        ) = tradingModule.getExecutionData(dexId, address(this), trade);

        return _executeInternal(trade, dexId, spender, target, msgValue, executionData);
    }

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

        // Curve doesn't support WETH (spender == address(0))
        if (trade.sellToken == address(WETH) && spender == Constants.ETH_ADDRESS) {
            uint256 withdrawAmount = _isExactIn(trade) ? trade.amount : trade.limit;
            WETH.withdraw(withdrawAmount);
        }

        (bool success, bytes memory returnData) = target.call{value: msgValue}(params);
        if (!success) revert TradeExecution(returnData);

        uint256 postTradeETHBalance = address(this).balance;

        // If the caller specifies that they want to receive WETH but we have received ETH,
        // wrap the ETH to WETH.
        if (trade.buyToken == address(WETH) && postTradeETHBalance > preTradeETHBalance) {
            uint256 depositAmount;
            unchecked { depositAmount = postTradeETHBalance - preTradeETHBalance; }
            WETH.deposit{value: depositAmount}();
        }
    }

    // @audit there should be an internal and external version of this method, the external method should
    // be exposed on the TradingModule directly
    function getLimitAmount(
        address tradingModule,
        uint16 tradeType,
        address sellToken,
        address buyToken,
        uint256 amount,
        uint32 slippageLimit
    ) external view returns (uint256 limitAmount) {
        // prettier-ignore
        (
            int256 oraclePrice, 
            int256 oracleDecimals
        ) = ITradingModule(tradingModule).getOraclePrice(
            sellToken,
            buyToken
        );

        require(oraclePrice >= 0); /// @dev Chainlink rate error
        require(oracleDecimals >= 0); /// @dev Chainlink decimals error

        uint256 sellTokenDecimals = 10 **
            (sellToken == address(0) ? 18 : IERC20(sellToken).decimals());
        uint256 buyTokenDecimals = 10 **
            (buyToken == address(0) ? 18 : IERC20(buyToken).decimals());

        // @audit what about EXACT_OUT_BATCH, won't that fall into the wrong else condition?
        if (TradeType(tradeType) == TradeType.EXACT_OUT_SINGLE) {
            // 0 means no slippage limit
            if (slippageLimit == 0) {
                return type(uint256).max;
            }
            // Invert oracle price
            // @audit comment this formula and re-arrange such that division is pushed to the end
            // to the extent possible
            oraclePrice = (oracleDecimals * oracleDecimals) / oraclePrice;
            // For exact out trades, limitAmount is the max amount of sellToken the DEX can
            // pull from the contract
            limitAmount =
                ((uint256(oraclePrice) +
                    ((uint256(oraclePrice) * uint256(slippageLimit)) /
                        SLIPPAGE_LIMIT_PRECISION)) * amount) /
                uint256(oracleDecimals);

            // limitAmount is in buyToken precision after the previous calculation,
            // convert it to sellToken precision
            limitAmount = (limitAmount * sellTokenDecimals) / buyTokenDecimals;
        } else {
            // 0 means no slippage limit
            if (slippageLimit == 0) {
                return 0;
            }
            // For exact in trades, limitAmount is the min amount of buyToken the contract
            // expects from the DEX
            limitAmount =
                ((uint256(oraclePrice) -
                    ((uint256(oraclePrice) * uint256(slippageLimit)) /
                        SLIPPAGE_LIMIT_PRECISION)) * amount) /
                uint256(oracleDecimals);

            // limitAmount is in sellToken precision after the previous calculation,
            // convert it to buyToken precision
            limitAmount = (limitAmount * buyTokenDecimals) / sellTokenDecimals;
        }
    }

}
