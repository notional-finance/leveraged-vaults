// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;
pragma abicoder v2;

import "../../../interfaces/trading/ITradingModule.sol";

library ZeroExAdapter {
    address constant ZERO_EX = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    struct BatchFillData {
        address inputToken;
        address outputToken;
        uint256 sellAmount;
        WrappedBatchCall[] calls;
    }

    struct WrappedBatchCall {
        bytes4 selector;
        uint256 sellAmount;
        bytes data;
    }

    struct MultiHopFillData {
        address[] tokens;
        uint256 sellAmount;
        WrappedMultiHopCall[] calls;
    }

    struct WrappedMultiHopCall {
        bytes4 selector;
        bytes data;
    }

    // ETH pseudo-token address used by 0x API.
    address private constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Byte size of Uniswap V3 encoded path addresses and pool fees
    uint256 private constant UNISWAP_V3_PATH_ADDRESS_SIZE = 20;
    uint256 private constant UNISWAP_V3_PATH_FEE_SIZE = 3;
    // Minimum byte size of a single hop Uniswap V3 encoded path (token address + fee + token adress)
    uint256 private constant UNISWAP_V3_SINGLE_HOP_PATH_SIZE =
        UNISWAP_V3_PATH_ADDRESS_SIZE +
            UNISWAP_V3_PATH_FEE_SIZE +
            UNISWAP_V3_PATH_ADDRESS_SIZE;
    // Byte size of one hop in the Uniswap V3 encoded path (token address + fee)
    uint256 private constant UNISWAP_V3_SINGLE_HOP_OFFSET_SIZE =
        UNISWAP_V3_PATH_ADDRESS_SIZE + UNISWAP_V3_PATH_FEE_SIZE;

    /// @notice Validate 0x calldata against the specified trade object
    /// Reference implementation
    /// https://github.com/SetProtocol/set-protocol-v2/blob/master/contracts/protocol/integration/exchange/ZeroExApiAdapter.sol
    function _validateExchangeData(address from, Trade calldata trade) internal pure {
        bytes calldata _data = trade.exchangeData;

        address inputToken;
        address outputToken;
        address recipient;
        bool supportsRecipient;
        uint256 inputTokenAmount;
        uint256 minOutputTokenAmount;

        {
            require(_data.length >= 4, "Invalid calldata");
            bytes4 selector;
            assembly {
                selector := and(
                    // Read the first 4 bytes of the _data array from calldata.
                    calldataload(add(36, calldataload(164))), // 164 = 5 * 32 + 4
                    0xffffffff00000000000000000000000000000000000000000000000000000000
                )
            }

            if (selector == 0x415565b0 || selector == 0x8182b61f) {
                // transformERC20(), transformERC20Staging()
                // prettier-ignore
                (
                    inputToken,
                    outputToken,
                    inputTokenAmount,
                    minOutputTokenAmount
                ) = abi.decode(_data[4:], (address, address, uint256, uint256));
            } else if (selector == 0xf7fcd384) {
                // sellToLiquidityProvider()
                // prettier-ignore
                (
                    inputToken, 
                    outputToken, 
                    , 
                    recipient, 
                    inputTokenAmount, 
                    minOutputTokenAmount
                ) = abi.decode(_data[4:], (address, address, address, address, uint256, uint256));
                supportsRecipient = true;
                if (recipient == address(0)) {
                    recipient = from;
                }
            } else if (selector == 0xd9627aa4) {
                // sellToUniswap()
                address[] memory path;
                // prettier-ignore
                (
                    path, 
                    inputTokenAmount, 
                    minOutputTokenAmount
                ) = abi.decode(_data[4:], (address[], uint256, uint256));
                require(path.length > 1, "Uniswap token path too short");
                inputToken = path[0];
                outputToken = path[path.length - 1];
            } else if (selector == 0xafc6728e) {
                // batchFill()
                BatchFillData memory fillData;
                // prettier-ignore
                (
                    fillData, 
                    minOutputTokenAmount
                ) = abi.decode(_data[4:], (BatchFillData, uint256));
                inputToken = fillData.inputToken;
                outputToken = fillData.outputToken;
                inputTokenAmount = fillData.sellAmount;
            } else if (selector == 0x21c184b6) {
                // multiHopFill()
                MultiHopFillData memory fillData;
                // prettier-ignore
                (
                    fillData, 
                    minOutputTokenAmount
                ) = abi.decode(_data[4:], (MultiHopFillData, uint256));
                require(
                    fillData.tokens.length > 1,
                    "Multihop token path too short"
                );
                inputToken = fillData.tokens[0];
                outputToken = fillData.tokens[fillData.tokens.length - 1];
                inputTokenAmount = fillData.sellAmount;
            } else if (selector == 0x6af479b2) {
                // sellTokenForTokenToUniswapV3()
                bytes memory encodedPath;
                // prettier-ignore
                (
                    encodedPath,
                    inputTokenAmount, 
                    minOutputTokenAmount, 
                    recipient
                ) = abi.decode(_data[4:], (bytes, uint256, uint256, address));
                supportsRecipient = true;
                if (recipient == address(0)) {
                    recipient = from;
                }
                (
                    inputToken,
                    outputToken
                ) = _decodeTokensFromUniswapV3EncodedPath(encodedPath);
            } else if (selector == 0x7a1eb1b9) {
                // multiplexBatchSellTokenForToken()
                // prettier-ignore
                (
                    inputToken, 
                    outputToken, 
                    , 
                    inputTokenAmount, 
                    minOutputTokenAmount
                ) = abi.decode(_data[4:], (address, address, uint256, uint256, uint256));
            } else if (selector == 0x0f3b31b2) {
                // multiplexMultiHopSellTokenForToken()
                address[] memory tokens;
                // prettier-ignore
                (
                    tokens, 
                    , 
                    inputTokenAmount, 
                    minOutputTokenAmount
                ) = abi.decode(_data[4:], (address[], uint256, uint256, uint256));
                require(tokens.length > 1, "Multihop token path too short");
                inputToken = tokens[0];
                outputToken = tokens[tokens.length - 1];
            } else {
                revert("Unsupported 0xAPI function selector");
            }
        }

        require(
            inputToken != ETH_ADDRESS && outputToken != ETH_ADDRESS,
            "ETH not supported"
        );
        require(inputToken == trade.sellToken, "Mismatched input token");
        require(outputToken == trade.buyToken, "Mismatched output token");
        require(
            !supportsRecipient || recipient == from,
            "Mismatched recipient"
        );
        require(
            inputTokenAmount == trade.amount,
            "Mismatched input token quantity"
        );
        require(
            minOutputTokenAmount >= trade.limit,
            "Mismatched output token quantity"
        );
    }

    // Decode input and output tokens from an arbitrary length encoded Uniswap V3 path
    function _decodeTokensFromUniswapV3EncodedPath(bytes memory encodedPath)
        private
        pure
        returns (address inputToken, address outputToken)
    {
        require(
            encodedPath.length >= UNISWAP_V3_SINGLE_HOP_PATH_SIZE,
            "UniswapV3 token path too short"
        );

        // UniswapV3 paths are packed encoded as (address(token0), uint24(fee), address(token1), [...])
        // We want the first and last token.
        uint256 numHops = (encodedPath.length - UNISWAP_V3_PATH_ADDRESS_SIZE) /
            UNISWAP_V3_SINGLE_HOP_OFFSET_SIZE;
        uint256 lastTokenOffset = numHops * UNISWAP_V3_SINGLE_HOP_OFFSET_SIZE;
        assembly {
            let p := add(encodedPath, 32)
            inputToken := shr(96, mload(p))
            p := add(p, lastTokenOffset)
            outputToken := shr(96, mload(p))
        }
    }

    function getExecutionData(address from, Trade calldata trade)
        internal view returns (
            address spender,
            address target,
            uint256 /* msgValue */,
            bytes memory executionCallData
        )
    {
        _validateExchangeData(from, trade);

        spender = ZERO_EX;
        target = ZERO_EX;
        // msgValue is always zero
        executionCallData = trade.exchangeData;
    }
}
