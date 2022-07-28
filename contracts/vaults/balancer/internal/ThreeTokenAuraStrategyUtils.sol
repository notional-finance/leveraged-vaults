// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StrategyContext, ThreeTokenPoolContext} from "../BalancerVaultTypes.sol";

library ThreeTokenAuraStrategyUtils {
    function _convertStrategyToUnderlying(
        StrategyContext memory strategyContext,
        ThreeTokenPoolContext memory poolContext,
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) internal view returns (int256 underlyingValue) {
        // TODO: implement this
    }
}
