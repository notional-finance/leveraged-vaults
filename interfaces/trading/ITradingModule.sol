// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

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

interface ITradingModule {
    function getSpender(uint16 dexId, Trade calldata trade)
        external
        view
        returns (address);

    function getExecutionData(
        uint16 dexId,
        address payable from,
        Trade calldata trade
    )
        external
        view
        returns (
            address target,
            uint256 value,
            bytes memory params
        );

    function setPriceOracle(address token, address oracle) external;

    function getOraclePrice(address inToken, address outToken)
        external
        view
        returns (uint256 answer, uint256 decimals);
}
