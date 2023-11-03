// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IRewardPool} from "../common/IRewardPool.sol";
import {IERC4626} from "../IERC4626.sol";

interface IAuraRewardPool is IRewardPool, IERC4626 { }

interface IAuraL2Coordinator {
    function auraOFT() external view returns (address);
}