// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IRewardPool} from "../common/IRewardPool.sol";

interface IAuraRewardPool is IRewardPool{
}

interface IAuraL2Coordinator {
    function auraOFT() external view returns (address);
}