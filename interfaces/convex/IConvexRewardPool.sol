// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IRewardPool} from "../common/IRewardPool.sol";

interface IConvexRewardPool is IRewardPool {
    function extraRewards(uint256 idx) external view returns (address);
    function extraRewardsLength() external view returns (uint256);
}
