// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {TradeHandler} from "../TradeHandler.sol";
import "@interfaces/trading/ITradingModule.sol";
import {ICamelotSwapRouter} from "@interfaces/camelot/ISwapRouter.sol";

library CamelotV3Adapter {

    struct CamelotV3BatchData { bytes path; }

    function _toAddress(bytes memory _bytes, uint256 _start) private pure returns (address) {
        // _bytes.length checked by the caller
        address tempAddress;

        assembly {
            tempAddress := div(
                mload(add(add(_bytes, 0x20), _start)),
                0x1000000000000000000000000
            )
        }

        return tempAddress;
    }

    function _getTokenAddress(address token) internal pure returns (address) {
        return token == Deployments.ETH_ADDRESS ? address(Deployments.WETH) : token;
    }

    function _exactInSingle(address from, Trade memory trade)
        private pure returns (bytes memory)
    {
        ICamelotSwapRouter.ExactInputSingleParams memory params = ICamelotSwapRouter.ExactInputSingleParams(
            _getTokenAddress(trade.sellToken),
            _getTokenAddress(trade.buyToken),
            from, trade.deadline, trade.amount, trade.limit, 0 // sqrtPriceLimitX96
        );

        return abi.encodeWithSelector(ICamelotSwapRouter.exactInputSingle.selector, params);
    }

    function _exactOutSingle(address from, Trade memory trade) private pure returns (bytes memory) {
        ICamelotSwapRouter.ExactOutputSingleParams memory params = ICamelotSwapRouter.ExactOutputSingleParams(
            _getTokenAddress(trade.sellToken),
            _getTokenAddress(trade.buyToken),
            from, trade.deadline, trade.amount, trade.limit, 0 // sqrtPriceLimitX96
        );

        return abi.encodeWithSelector(ICamelotSwapRouter.exactOutputSingle.selector, params);
    }

    function _exactInBatch(address from, Trade memory trade) private pure returns (bytes memory) {
        CamelotV3BatchData memory data = abi.decode(trade.exchangeData, (CamelotV3BatchData));

        // Validate path EXACT_IN = [sellToken, fee, ... buyToken]
        require(32 <= data.path.length);
        require(_toAddress(data.path, 0) == _getTokenAddress(trade.sellToken));
        require(_toAddress(data.path, data.path.length - 20) == _getTokenAddress(trade.buyToken));

        ICamelotSwapRouter.ExactInputParams memory params = ICamelotSwapRouter.ExactInputParams(
            data.path, from, trade.deadline, trade.amount, trade.limit
        );

        return abi.encodeWithSelector(ICamelotSwapRouter.exactInput.selector, params);
    }

    function _exactOutBatch(address from, Trade memory trade) private pure returns (bytes memory) {
        CamelotV3BatchData memory data = abi.decode(trade.exchangeData, (CamelotV3BatchData));

        // Validate path EXACT_OUT = [buyToken, fee, ... sellToken]
        require(32 <= data.path.length);
        require(_toAddress(data.path, 0) == _getTokenAddress(trade.buyToken));
        require(_toAddress(data.path, data.path.length - 20) == _getTokenAddress(trade.sellToken));

        ICamelotSwapRouter.ExactOutputParams memory params = ICamelotSwapRouter.ExactOutputParams(
            data.path, from, trade.deadline, trade.amount, trade.limit
        );

        return abi.encodeWithSelector(ICamelotSwapRouter.exactOutput.selector, params);
    }

    function getExecutionData(address from, Trade memory trade)
        internal pure returns (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionCallData
        )
    {
        spender = address(Deployments.CAMELOT_V3_ROUTER);
        target = address(Deployments.CAMELOT_V3_ROUTER);
        // msgValue is always zero for uniswap
        msgValue = 0;

        if (trade.tradeType == TradeType.EXACT_IN_SINGLE) {
            executionCallData = _exactInSingle(from, trade);
        } else if (trade.tradeType == TradeType.EXACT_OUT_SINGLE) {
            executionCallData = _exactOutSingle(from, trade);
        } else if (trade.tradeType == TradeType.EXACT_IN_BATCH) {
            executionCallData = _exactInBatch(from, trade);
        } else if (trade.tradeType == TradeType.EXACT_OUT_BATCH) {
            executionCallData = _exactOutBatch(from, trade);
        }
    }
}