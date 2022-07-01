// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

contract MockZeroEx {
    constructor() {}

    function sellTokenForTokenToUniswapV3(
        bytes memory encodedPath,
        uint256 sellAmount,
        uint256 minBuyAmount,
        address recipient
    ) external returns (uint256 buyAmount) {}
}
