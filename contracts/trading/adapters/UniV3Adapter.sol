// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "../../../interfaces/trading/IExchangeAdapter.sol";
import "../../../interfaces/uniswap/v3/ISwapRouter.sol";

contract UniV3Adapter is IExchangeAdapter {
    ISwapRouter public immutable ROUTER;

    struct UniV3SingleData { uint24 fee; }

    struct UniV3BatchData { bytes path; }

    constructor(ISwapRouter _router) { ROUTER = _router; }

    function _exactInSingle(address from, Trade memory trade)
        private pure returns (bytes memory)
    {
        UniV3SingleData memory data = abi.decode(trade.exchangeData, (UniV3SingleData));

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            trade.sellToken, trade.buyToken, data.fee, from, trade.deadline, trade.amount, trade.limit, 0 // sqrtPriceLimitX96
        );

        return abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params);
    }

    function _exactOutSingle(address from, Trade memory trade)
        private pure returns (bytes memory)
    {
        UniV3SingleData memory data = abi.decode(trade.exchangeData, (UniV3SingleData));

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
            trade.sellToken, trade.buyToken, data.fee, from, trade.deadline, trade.amount, trade.limit, 0 // sqrtPriceLimitX96
        );

        return abi.encodeWithSelector(ISwapRouter.exactOutputSingle.selector, params);
    }

    function _exactInBatch(address from, Trade memory trade)
        private pure returns (bytes memory)
    {
        UniV3BatchData memory data = abi.decode(trade.exchangeData, (UniV3BatchData));

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams(
            data.path, from, trade.deadline, trade.amount, trade.limit
        );

        return abi.encodeWithSelector(ISwapRouter.exactInput.selector, params);
    }

    function _exactOutBatch(address from, Trade memory trade)
        private pure returns (bytes memory)
    {
        UniV3BatchData memory data = abi.decode(trade.exchangeData, (UniV3BatchData));

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams(
            data.path, from, trade.deadline, trade.amount, trade.limit
        );

        return abi.encodeWithSelector(ISwapRouter.exactOutput.selector, params);
    }

    function getExecutionData(address from, Trade calldata trade)
        external view override returns (
            address spender,
            address target,
            uint256 /* msgValue */,
            bytes memory executionCallData
        )
    {
        spender = address(ROUTER);
        target = address(ROUTER);
        // msgValue is always zero for uniswap

        if (trade.tradeType == TradeType.EXACT_IN_SINGLE) {
            executionCallData = _exactInSingle(from, trade);
        } else if (trade.tradeType == TradeType.EXACT_OUT_SINGLE) {
            executionCallData = _exactOutSingle(from, trade);
        } else if (trade.tradeType == TradeType.EXACT_IN_BATCH) {
            executionCallData = _exactInBatch(from, trade);
        } else if (trade.tradeType == TradeType.EXACT_OUT_BATCH) {
            executionCallData = _exactOutBatch(from, trade);
        }

        revert InvalidTrade();
    }
}
