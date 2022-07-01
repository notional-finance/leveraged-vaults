// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../../../interfaces/trading/ITradingModule.sol";
import "../../../interfaces/uniswap/v2/IUniV2Router2.sol";

library UniV2Adapter {
    IUniV2Router2 public constant ROUTER = IUniV2Router2(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    struct UniV2Data { address[] path; }

    function getExecutionData(address from, Trade calldata trade)
        internal view returns (
            address spender,
            address target,
            uint256 /* msgValue */,
            bytes memory executionCallData
        )
    {
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
