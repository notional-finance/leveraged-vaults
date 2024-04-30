// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "@interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "@interfaces/convex/IConvexRewardPool.sol";
import {Curve2TokenPoolMixin, DeploymentParams} from "./mixins/Curve2TokenPoolMixin.sol";

contract Curve2TokenVault is Curve2TokenPoolMixin {
    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        Curve2TokenPoolMixin(notional_, params) {}

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Curve2TokenVault"));
    }
}