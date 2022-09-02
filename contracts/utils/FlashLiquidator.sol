// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IFlashLoanRecipient} from "../../interfaces/balancer/IFlashLoanRecipient.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {BoringOwnable} from "./BoringOwnable.sol";
import {Deployments} from "../global/Deployments.sol";

contract FlashLiquidator is BoringOwnable, IFlashLoanRecipient {
    using TokenUtils for IERC20;

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    function approveTokens(IERC20[] calldata tokens) external onlyOwner {
        for (uint256 i; i < tokens.length; i++) {
            tokens[i].checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
        }
    }

    function flashLiquidate(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external onlyOwner {
        Deployments.BALANCER_VAULT.flashLoan(address(this), tokens, amounts, userData);
    }

    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external {
        require(msg.sender == address(Deployments.BALANCER_VAULT));
    }    
}