// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "../../../interfaces/trading/IExchangeAdapter.sol";
import "../../../interfaces/uniswap/v2/IUniV2Router2.sol";

contract UniV2Adapter is IExchangeAdapter {
    IUniV2Router2 public immutable ROUTER;

    struct UniV2Data { address[] path; }

    constructor(IUniV2Router2 _router) { ROUTER = _router; }

    function getExecutionData(address from, Trade calldata trade)
        external view override returns (
            address spender,
            address target,
            uint256 /* msgValue */,
            bytes memory executionCallData
        )
    {
        if (trade.tradeType == TradeType.EXACT_OUT_BATCH) revert InvalidTrade();
        TradeType tradeType = trade.tradeType;
        UniV2Data memory data = abi.decode(trade.exchangeData, (UniV2Data));

        spender = address(ROUTER);
        target = address(ROUTER);
        // msgValue is always zero for uniswap

        if (
            tradeType == TradeType.EXACT_IN_SINGLE ||
            tradeType == TradeType.EXACT_IN_BATCH
        ) {
            executionCallData = abi.encodeWithSelector(
                IUniV2Router2.swapExactTokensForTokens.selector,
                trade.amount,
                trade.limit,
                data.path,
                from,
                trade.deadline
            );
        } else if (
            tradeType == TradeType.EXACT_OUT_SINGLE ||
            tradeType == TradeType.EXACT_OUT_BATCH
        ) {
            executionCallData = abi.encodeWithSelector(
                IUniV2Router2.swapTokensForExactTokens.selector,
                trade.amount,
                trade.limit,
                data.path,
                from,
                trade.deadline
            );
        }
    }
}
