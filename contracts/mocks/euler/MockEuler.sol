// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IEulerMarkets } from "../../../interfaces/euler/IEulerMarkets.sol";
import { IEulerDToken } from "../../../interfaces/euler/IEulerDToken.sol";
import { IEulerFlashLoanReceiver } from "../../../interfaces/euler/IEulerFlashLoanReceiver.sol";
import { IERC20 } from "../../../interfaces/IERC20.sol";

contract MockEuler is IEulerMarkets, IEulerDToken {
    IERC20 public immutable TOKEN;
    address public owner;

    constructor(IERC20 token_) {
        TOKEN = token_;
        owner = msg.sender;
    }

    function underlyingToDToken(address underlying) external override view returns (address) {
        return address(this);
    }

    function flashLoan(uint amount, bytes calldata data) external override {
        uint256 currentBalance = TOKEN.balanceOf(address(this));
        TOKEN.transfer(msg.sender, amount);
        IEulerFlashLoanReceiver(msg.sender).onFlashLoan(data);
        require(TOKEN.balanceOf(address(this)) == currentBalance, "loan repayment");
    }

    function withdraw() external {
        require(msg.sender == owner);
        TOKEN.transfer(msg.sender, TOKEN.balanceOf(address(this)));
    }
}
