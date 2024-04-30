// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {IERC20, TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {ConvexStakingMixin, ConvexVaultDeploymentParams} from "./mixins/ConvexStakingMixin.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IConvexBooster, IConvexBoosterArbitrum} from "@interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "@interfaces/convex/IConvexRewardPool.sol";
import {
    CurveInterface,
    ICurvePool,
    ICurve2TokenPoolV1,
    ICurve2TokenPoolV2,
    ICurveStableSwapNG
} from "@interfaces/curve/ICurvePool.sol";

contract Curve2TokenConvexVault is ConvexStakingMixin {
    // This contract does not properly support Curve pools where one of the tokens is
    // held as an LP token. However, unlike Balancer pools there is no reliable way to
    // determine if the token held in the Curve pool is an LP token or not, therefore
    // we do not have an explicit check here.
    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        ConvexStakingMixin(notional_, params) {}

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Curve2TokenConvexVault"));
    }
}
