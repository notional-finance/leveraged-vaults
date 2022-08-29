// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Deployments} from "../../global/Deployments.sol";
import {Trade} from "../../../interfaces/trading/ITradingModule.sol";

library ZeroExAdapter {
    function getExecutionData(address from, Trade calldata trade)
        internal view returns (
            address spender,
            address target,
            uint256 /* msgValue */,
            bytes memory executionCallData
        )
    {
        spender = Deployments.ZERO_EX;
        target = Deployments.ZERO_EX;
        // msgValue is always zero
        executionCallData = trade.exchangeData;
    }
}
