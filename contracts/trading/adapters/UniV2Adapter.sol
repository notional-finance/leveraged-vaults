// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "../../../interfaces/trading/IExchangeAdapter.sol";
import "../../../interfaces/uniswap/v2/IUniV2Router2.sol";

contract UniV2Adapter is IExchangeAdapter {
    IUniV2Router2 public immutable ROUTER;

    struct UniV2Data {
        address[] path;
    }

    constructor(IUniV2Router2 _router) {
        ROUTER = _router;
    }

    function getExecutionData(address payable from, Trade calldata trade)
        external
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(TradeType(trade.tradeType) <= TradeType.EXACT_OUT_BATCH, "invalid type");

        TradeType tradeType = TradeType(trade.tradeType);
        UniV2Data memory data = abi.decode(trade.exchangeData, (UniV2Data));

        if (
            tradeType == TradeType.EXACT_IN_SINGLE ||
            tradeType == TradeType.EXACT_IN_BATCH
        ) {
            return (
                address(ROUTER),
                0,
                abi.encodeWithSelector(
                    IUniV2Router2.swapExactTokensForTokens.selector,
                    trade.amount,
                    trade.limit,
                    data.path,
                    from,
                    trade.deadline
                )
            );
        } else if (
            tradeType == TradeType.EXACT_OUT_SINGLE ||
            tradeType == TradeType.EXACT_OUT_BATCH
        ) {
            return (
                address(ROUTER),
                0,
                abi.encodeWithSelector(
                    IUniV2Router2.swapTokensForExactTokens.selector,
                    trade.amount,
                    trade.limit,
                    data.path,
                    from,
                    trade.deadline
                )
            );
        }
    }

    function getSpender(Trade calldata trade)
        external
        view
        override
        returns (address)
    {
        return address(ROUTER);
    }

    function getLiquidity(bytes calldata params)
        external
        view
        override
        returns (address[] memory, uint256[] memory)
    {
        address[] memory tokens = new address[](0);
        uint256[] memory balances = new uint256[](0);

        return (tokens, balances);
    }
}
