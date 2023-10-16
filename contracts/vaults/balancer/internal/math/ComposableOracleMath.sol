// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ComposableOracleContext, BalancerComposablePoolContext, StrategyContext} from "../../BalancerVaultTypes.sol";
import {TwoTokenPoolContext} from "../../../common/VaultTypes.sol";
import {VaultConstants} from "../../../common/VaultConstants.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Errors} from "../../../../global/Errors.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {StableMath} from "./StableMath.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library ComposableOracleMath {
    using TypeConvert for int256;
    using StrategyUtils for StrategyContext;

    function _getSpotPrice(
        ComposableOracleContext memory oracleContext, 
        BalancerComposablePoolContext memory poolContext, 
        uint256 index1,
        uint256 index2
    ) internal view returns (uint256 spotPrice) {
        require(
            index1 != poolContext.bptIndex && index1 < poolContext.basePool.tokens.length
        ); /// @dev invalid token index
        require(
            index2 != poolContext.bptIndex && index2 < poolContext.basePool.tokens.length
        ); /// @dev invalid token index

        if (index1 == index2) {
            return BalancerConstants.BALANCER_PRECISION;
        }

        /// Apply scale factors
        /// @notice poolContext balances are always in BALANCER_PRECISION (1e18)
        uint256 balanceX = 
            poolContext.basePool.balances[index1] * poolContext.scalingFactors[index1] 
            / BalancerConstants.BALANCER_PRECISION;
        uint256 balanceY = 
            poolContext.basePool.balances[index2] * poolContext.scalingFactors[index2] 
            / BalancerConstants.BALANCER_PRECISION;

        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, StableMath._balances(balanceX, balanceY), true // round up
        );

        spotPrice = StableMath._calcSpotPrice({
            amplificationParameter: oracleContext.ampParam,
            invariant: invariant,
            balanceX: balanceX,
            balanceY: balanceY
        });

        /// Apply secondary scale factor in reverse
        uint256 scaleFactor = poolContext.scalingFactors[index2] * BalancerConstants.BALANCER_PRECISION 
            / poolContext.scalingFactors[index1];
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / scaleFactor;

        // Convert precision back to 1e18 after downscaling by scaleFactor
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / (10**poolContext.basePool.decimals[index2]);
    }
}
