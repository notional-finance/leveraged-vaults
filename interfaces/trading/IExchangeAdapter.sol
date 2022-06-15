// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "./ITradingModule.sol";

interface IExchangeAdapter {
    function getExecutionData(address payable from, Trade calldata trade)
        external
        view
        returns (
            address target,
            uint256 value,
            bytes memory params
        );

    function getSpender(Trade calldata trade) external view returns (address);

    function getLiquidity(bytes calldata params)
        external
        view
        returns (address[] memory, uint256[] memory);
}
