// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {IERC20} from "@interfaces/IERC20.sol";

interface IeETH is IERC20 { }

interface IweETH is IERC20 {
    function wrap(uint256 eETHDeposit) external returns (uint256 weETHMinted);
    function unwrap(uint256 weETHDeposit) external returns (uint256 eETHMinted);
}

interface ILiquidityPool {
    function deposit() external payable returns (uint256 eETHMinted);
    function requestWithdraw(address requester, uint256 eETHAmount) external returns (uint256 requestId);
}

interface IWithdrawRequestNFT {
    function ownerOf(uint256 requestId) external view returns (address);
    function isFinalized(uint256 requestId) external view returns (bool);
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
    function claimWithdraw(uint256 requestId) external;
    function finalizeRequests(uint256 requestId) external;
}
