// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import "../chainlink/AggregatorV2V3Interface.sol";

enum DexId {
    _UNUSED,        // flag = 1,  enum = 0
    UNISWAP_V2,     // flag = 2,  enum = 1
    UNISWAP_V3,     // flag = 4,  enum = 2
    ZERO_EX,        // flag = 8,  enum = 3
    BALANCER_V2,    // flag = 16, enum = 4
    // NOTE: this id is unused in the TradingModule
    CURVE,          // flag = 32, enum = 5
    NOTIONAL_VAULT, // flag = 64, enum = 6
    CURVE_V2,       // flag = 128, enum = 7
    CAMELOT_V3      // flag = 256, enum = 8
}

enum TradeType {
    EXACT_IN_SINGLE,  // flag = 1
    EXACT_OUT_SINGLE, // flag = 2
    EXACT_IN_BATCH,   // flag = 4
    EXACT_OUT_BATCH   // flag = 8
}

struct Trade {
    TradeType tradeType;
    address sellToken;
    address buyToken;
    uint256 amount;
    /// minBuyAmount or maxSellAmount
    uint256 limit;
    uint256 deadline;
    bytes exchangeData;
}

error InvalidTrade();
error DynamicTradeFailed();
error TradeFailed();

interface ITradingModule {
    struct TokenPermissions {
        bool allowSell;
        /// @notice allowed DEXes
        uint32 dexFlags;
        /// @notice allowed trade types
        uint32 tradeTypeFlags; 
    }

    event TradeExecuted(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    );

    event PriceOracleUpdated(address token, address oracle);
    event MaxOracleFreshnessUpdated(uint32 currentValue, uint32 newValue);
    event TokenPermissionsUpdated(address sender, address token, TokenPermissions permissions);

    function tokenWhitelist(address spender, address token) external view returns (
        bool allowSell, uint32 dexFlags, uint32 tradeTypeFlags
    );

    function priceOracles(address token) external view returns (AggregatorV2V3Interface oracle, uint8 rateDecimals);

    function getExecutionData(uint16 dexId, address from, Trade calldata trade)
        external view returns (
            address spender,
            address target,
            uint256 value,
            bytes memory params
        );

    function setMaxOracleFreshness(uint32 newMaxOracleFreshnessInSeconds) external;

    function setPriceOracle(address token, AggregatorV2V3Interface oracle) external;

    function setTokenPermissions(
        address sender, 
        address token, 
        TokenPermissions calldata permissions
    ) external;

    function getOraclePrice(address inToken, address outToken)
        external view returns (int256 answer, int256 decimals);

    function executeTrade(
        uint16 dexId,
        Trade calldata trade
    ) external payable returns (uint256 amountSold, uint256 amountBought);

    function executeTradeWithDynamicSlippage(
        uint16 dexId,
        Trade memory trade,
        uint32 dynamicSlippageLimit
    ) external payable returns (uint256 amountSold, uint256 amountBought);

    function getLimitAmount(
        address from,
        TradeType tradeType,
        address sellToken,
        address buyToken,
        uint256 amount,
        uint32 slippageLimit
    ) external view returns (uint256 limitAmount);

    function canExecuteTrade(address from, uint16 dexId, Trade calldata trade) external view returns (bool);
}