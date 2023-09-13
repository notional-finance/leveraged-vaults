// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IRewardPool} from "../common/IRewardPool.sol";

interface IConvexRewardPool is IRewardPool {
    function extraRewards(uint256 idx) external view returns (address);
    function extraRewardsLength() external view returns (uint256);
}


interface IConvexRewardPoolArbitrum {
    function rewardLength() external view returns (uint256);
    function rewards(uint256 i) external view returns (address, uint256, uint256);
    function getReward(address _account) external;
    function convexBooster() external view returns (address);
    function balanceOf(address _account) external view returns(uint256);
    function withdraw(uint256 amount, bool claim) external returns(bool);
    function convexPoolId() external view returns (uint256);
}
