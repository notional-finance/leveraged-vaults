// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IConvexStakingProxy {
    function rewardToken() external view returns (address);
    function stakingToken() external view returns (address);
}
