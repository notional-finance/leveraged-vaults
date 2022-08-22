// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../../../interfaces/trading/ITradingModule.sol";
import "../../../interfaces/uniswap/v2/IUniV2Router2.sol";
import {Deployments} from "../../global/Deployments.sol";

library UniV2Adapter {

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

        spender = address(Deployments.UNIV2_ROUTER);
        target = address(Deployments.UNIV2_ROUTER);
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
