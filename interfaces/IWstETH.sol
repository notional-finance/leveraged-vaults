// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IWstETH {
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function stETH() external view returns (address);
}