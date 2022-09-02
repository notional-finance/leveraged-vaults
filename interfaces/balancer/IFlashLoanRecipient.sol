// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IERC20} from "../IERC20.sol";

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}
