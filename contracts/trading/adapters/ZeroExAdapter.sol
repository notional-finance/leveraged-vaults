// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {Trade} from "@interfaces/trading/ITradingModule.sol";

library ZeroExAdapter {
    /// @dev executeTrade validates pre and post trade balances and also
    /// sets and revokes all approvals. We are also only calling a trusted
    /// zero ex proxy in this case. Therefore no order validation is done
    /// to allow for flexibility.
    function getExecutionData(address /* from */, Trade memory trade)
        internal pure returns (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionCallData
        )
    {
        spender = Deployments.ZERO_EX;
        target = Deployments.ZERO_EX;
        executionCallData = trade.exchangeData;
        // msgValue is always zero
        msgValue = 0;
    }
}