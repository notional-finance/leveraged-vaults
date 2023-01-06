// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IConvexRewardPool {
    function balanceOf(address _account) external view returns(uint256);
    function pid() external view returns(uint256);
    function operator() external view returns(address);
}
