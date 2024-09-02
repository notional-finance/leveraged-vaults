// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface ICurveGauge {
    function claim_rewards() external;
    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;
}