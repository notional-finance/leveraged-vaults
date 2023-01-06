// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ConvexVaultDeploymentParams, Curve2TokenConvexStrategyContext} from "../CurveVaultTypes.sol";
import {Curve2TokenPoolMixin} from "./Curve2TokenPoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";

abstract contract Curve2TokenVaultMixin is Curve2TokenPoolMixin {
    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params)
        Curve2TokenPoolMixin(notional_, params) { }

    function _strategyContext() internal view returns (Curve2TokenConvexStrategyContext memory) {
        return Curve2TokenConvexStrategyContext({
            baseStrategy: _baseStrategyContext(),
            poolContext: _twoTokenPoolContext()
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
