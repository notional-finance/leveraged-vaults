// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@interfaces/trading/ITradingModule.sol";
import "@interfaces/uniswap/v2/IUniV2Router2.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";

library UniV2Adapter {

    struct UniV2Data { address[] path; }

    function getExecutionData(address from, Trade memory trade)
        internal pure returns (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionCallData
        )
    {
        TradeType tradeType = trade.tradeType;
        UniV2Data memory data = abi.decode(trade.exchangeData, (UniV2Data));

        target = address(Deployments.UNIV2_ROUTER);

        if (
            tradeType == TradeType.EXACT_IN_SINGLE ||
            tradeType == TradeType.EXACT_IN_BATCH
        ) {
            if (trade.sellToken == Constants.ETH_ADDRESS) {
                require(data.path[0] == address(Deployments.WETH));
                require(data.path[data.path.length - 1] == trade.buyToken);

                msgValue = trade.amount;
                // spender = address(0)
                executionCallData = abi.encodeWithSelector(
                    IUniV2Router2.swapExactETHForTokens.selector,
                    trade.limit,
                    data.path,
                    from,
                    trade.deadline
                );
            } else if (trade.buyToken == Constants.ETH_ADDRESS) {
                require(data.path[0] == trade.sellToken);
                require(data.path[data.path.length - 1] == address(Deployments.WETH));

                spender = address(Deployments.UNIV2_ROUTER);
                executionCallData = abi.encodeWithSelector(
                    IUniV2Router2.swapExactTokensForETH.selector,
                    trade.amount,
                    trade.limit,
                    data.path,
                    from,
                    trade.deadline
                );
            } else {
                require(data.path[0] == trade.sellToken);
                require(data.path[data.path.length - 1] == trade.buyToken);

                spender = address(Deployments.UNIV2_ROUTER);
                executionCallData = abi.encodeWithSelector(
                    IUniV2Router2.swapExactTokensForTokens.selector,
                    trade.amount,
                    trade.limit,
                    data.path,
                    from,
                    trade.deadline
                );
            }
        } else if (
            tradeType == TradeType.EXACT_OUT_SINGLE ||
            tradeType == TradeType.EXACT_OUT_BATCH
        ) {
            if (trade.sellToken == Constants.ETH_ADDRESS) {
                require(data.path[0] == address(Deployments.WETH));
                require(data.path[data.path.length - 1] == trade.buyToken);

                msgValue = trade.limit;
                // spender = address(0)
                executionCallData = abi.encodeWithSelector(
                    IUniV2Router2.swapETHForExactTokens.selector,
                    trade.amount,
                    data.path,
                    from,
                    trade.deadline
                );
            } else if (trade.buyToken == Constants.ETH_ADDRESS) {
                require(data.path[0] == trade.sellToken);
                require(data.path[data.path.length - 1] == address(Deployments.WETH));

                spender = address(Deployments.UNIV2_ROUTER);
                executionCallData = abi.encodeWithSelector(
                    IUniV2Router2.swapTokensForExactETH.selector,
                    trade.amount,
                    trade.limit,
                    data.path,
                    from,
                    trade.deadline
                );
            } else {
                require(data.path[0] == trade.sellToken);
                require(data.path[data.path.length - 1] == trade.buyToken);

                spender = address(Deployments.UNIV2_ROUTER);
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
}