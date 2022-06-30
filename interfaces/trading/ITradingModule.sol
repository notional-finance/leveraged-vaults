// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../chainlink/AggregatorV2V3Interface.sol";

enum DexId {
    UNISWAP_V2,
    UNISWAP_V3,
    ZERO_EX,
    BALANCER_V2,
    CURVE,
    NOTIONAL_VAULT
}

enum TradeType {
    EXACT_IN_SINGLE,
    EXACT_OUT_SINGLE,
    EXACT_IN_BATCH,
    EXACT_OUT_BATCH
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

interface ITradingModule {
    function getExecutionData(uint16 dexId, address from, Trade calldata trade)
        external view returns (
            address spender,
            address target,
            uint256 value,
            bytes memory params
        );

    function setPriceOracle(address token, AggregatorV2V3Interface oracle) external;

    function getOraclePrice(address inToken, address outToken)
        external view returns (int256 answer, int256 decimals);
}
