// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "./ITradingModule.sol";

interface IExchangeAdapter {
    /// @notice Error on invalid trade data
    error InvalidTrade();

    /// @notice Returns required parameters for a given exchange
    /// @param from the address that will execute the trade
    /// @param trade trade calldata parameters
    /// @return spender address that requires approval for the sell token
    /// @return target address to call
    /// @return msgValue amount of ETH to forward (if any)
    /// @return executionCallData to call the contract with
    function getExecutionData(address from, Trade calldata trade)
        external view returns (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionCallData
        );
}
