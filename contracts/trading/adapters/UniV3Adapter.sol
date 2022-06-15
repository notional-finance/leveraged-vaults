// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "../../../interfaces/trading/IExchangeAdapter.sol";
import "../../../interfaces/uniswap/v3/ISwapRouter.sol";

contract UniV3Adapter is IExchangeAdapter {
    ISwapRouter public immutable ROUTER;

    struct UniV3SingleData {
        uint24 fee;
    }

    struct UniV3BatchData {
        bytes path;
    }

    constructor(ISwapRouter _router) {
        ROUTER = _router;
    }

    function _exactInSingle(address payable from, Trade memory trade)
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        UniV3SingleData memory data = abi.decode(
            trade.exchangeData,
            (UniV3SingleData)
        );

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                trade.sellToken,
                trade.buyToken,
                data.fee,
                from,
                trade.deadline,
                trade.amount,
                trade.limit,
                0
            );

        return (
            address(ROUTER),
            0,
            abi.encodeWithSelector(
                ISwapRouter.exactInputSingle.selector,
                params
            )
        );
    }

    function _exactOutSingle(address payable from, Trade memory trade)
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        UniV3SingleData memory data = abi.decode(
            trade.exchangeData,
            (UniV3SingleData)
        );

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams(
                trade.sellToken,
                trade.buyToken,
                data.fee,
                from,
                trade.deadline,
                trade.amount,
                trade.limit,
                0
            );

        return (
            address(ROUTER),
            0,
            abi.encodeWithSelector(
                ISwapRouter.exactOutputSingle.selector,
                params
            )
        );
    }

    function _exactInBatch(address payable from, Trade memory trade)
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        UniV3BatchData memory data = abi.decode(
            trade.exchangeData,
            (UniV3BatchData)
        );

        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams(
                data.path,
                from,
                trade.deadline,
                trade.amount,
                trade.limit
            );

        return (
            address(ROUTER),
            0,
            abi.encodeWithSelector(ISwapRouter.exactInput.selector, params)
        );
    }

    function _exactOutBatch(address payable from, Trade memory trade)
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        UniV3BatchData memory data = abi.decode(
            trade.exchangeData,
            (UniV3BatchData)
        );

        ISwapRouter.ExactOutputParams memory params = ISwapRouter
            .ExactOutputParams(
                data.path,
                from,
                trade.deadline,
                trade.amount,
                trade.limit
            );

        return (
            address(ROUTER),
            0,
            abi.encodeWithSelector(ISwapRouter.exactOutput.selector, params)
        );
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
        if (TradeType(trade.tradeType) == TradeType.EXACT_IN_SINGLE) {
            return _exactInSingle(from, trade);
        } else if (TradeType(trade.tradeType) == TradeType.EXACT_OUT_SINGLE) {
            return _exactOutSingle(from, trade);
        } else if (TradeType(trade.tradeType) == TradeType.EXACT_IN_BATCH) {
            return _exactInBatch(from, trade);
        } else if (TradeType(trade.tradeType) == TradeType.EXACT_OUT_BATCH) {
            return _exactOutBatch(from, trade);
        }

        revert("invalid type");
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
