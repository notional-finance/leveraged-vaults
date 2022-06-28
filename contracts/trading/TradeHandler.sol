// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/WETH9.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/trading/ITradingModule.sol";

/// @notice TradeHandler is an internal library to be compiled into StrategyVaults to interact
/// with the TradeModule and execute trades
library TradeHandler {
    using TradeHandler for Trade;

    error ERC20Error();
    error TradeExecution(bytes returnData);
    error PreValidationExactIn(uint256 maxAmountIn, uint256 preTradeSellBalance);
    error PreValidationExactOut(uint256 maxAmountIn, uint256 preTradeSellBalance);
    error PostValidationExactIn(uint256 minAmountOut, uint256 amountReceived);
    error PostValidationExactOut(uint256 exactAmountOut, uint256 amountReceived);

    address public constant ETH_ADDRESS = address(0);
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
        if (spender != ETH_ADDRESS && DexId(dexId) != DexId.NOTIONAL_VAULT) {
            _approve(trade, spender);
        }

        _executeTrade(target, msgValue, executionData, spender, trade);

        // Get post-trade token balances
        (uint256 postTradeSellBalance, uint256 postTradeBuyBalance) = _getBalances(trade);

        _postValidate(trade, postTradeBuyBalance - preTradeBuyBalance);

        // No need to revoke ETH trades
        if (spender != ETH_ADDRESS && DexId(dexId) != DexId.NOTIONAL_VAULT) {
            _revoke(trade, spender);
        }

        amountSold = preTradeSellBalance - postTradeSellBalance;
        amountBought = postTradeBuyBalance - preTradeBuyBalance;

        emit TradeExecuted(trade.sellToken, trade.buyToken, amountSold, amountBought);
    }

    function _getBalances(Trade memory trade) private view returns (uint256, uint256) {
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
        IERC20(trade.sellToken).approve(spender, allowance);
        _checkReturnCode();
    }

    /// @notice Revoke exchange approvals
    function _revoke(Trade memory trade, address spender) private {
        IERC20(trade.sellToken).approve(spender, 0);
        _checkReturnCode();
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
        if (trade.sellToken == address(WETH) && spender == ETH_ADDRESS) {
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

    // Supports checking return codes on non-standard ERC20 contracts
    function _checkReturnCode() private pure {
        bool success;
        uint256[1] memory result;
        assembly {
            switch returndatasize()
                case 0 {
                    // This is a non-standard ERC-20
                    success := 1 // set success to true
                }
                case 32 {
                    // This is a compliant ERC-20
                    returndatacopy(result, 0, 32)
                    success := mload(result) // Set `success = returndata` of external call
                }
                default {
                    // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }

        if (!success) revert ERC20Error();
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
            (sellToken == address(0) ? 18 : ERC20(sellToken).decimals());
        uint256 buyTokenDecimals = 10 **
            (buyToken == address(0) ? 18 : ERC20(buyToken).decimals());

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

    // @audit maybe call this method something more specific for the balancer vault
    function approveTokens(
        address balancerVault,
        address underylingToken,
        address secondaryToken,
        address balancerPool,
        address liquidityGauge,
        address vebalDelegator
    ) external {
        // Allow Balancer vault to pull UNDERLYING_TOKEN
        if (address(underylingToken) != address(0)) {
            IERC20(underylingToken).approve(
                balancerVault,
                type(uint256).max
            );
            _checkReturnCode();
        }
        // Allow balancer vault to pull SECONDARY_TOKEN
        if (address(secondaryToken) != address(0)) {
            IERC20(secondaryToken).approve(balancerVault, type(uint256).max);
            _checkReturnCode();
        }
        // Allow LIQUIDITY_GAUGE to pull BALANCER_POOL_TOKEN
        IERC20(balancerPool).approve(liquidityGauge, type(uint256).max);
        _checkReturnCode();

        // Allow VEBAL_DELEGATOR to pull LIQUIDITY_GAUGE tokens
        IERC20(liquidityGauge).approve(vebalDelegator, type(uint256).max);
        _checkReturnCode();
    }
}
