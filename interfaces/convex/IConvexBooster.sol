// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IConvexBooster {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
    function stakerRewards() external view returns(address);
}

interface IConvexBoosterArbitrum {
    function deposit(uint256 _pid, uint256 _amount) external returns(bool);
}