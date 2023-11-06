// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ComposableOracleContext, BalancerComposablePoolContext} from "../../BalancerVaultTypes.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {StableMath} from "./StableMath.sol";

/**
 * Helper function for calculating the spot price
 */
library ComposableOracleMath {
    using TypeConvert for int256;

    /// @notice Gets the current spot price of poolTokens[index1] with respect to poolTokens[index2]
    /// @param oracleContext oracle context
    /// @param poolContext pool context
    /// @param index1 first token index
    /// @param index2 second token index
    /// @return spotPrice spot price of 1 vault share
    function _getSpotPrice(
        ComposableOracleContext memory oracleContext, 
        BalancerComposablePoolContext memory poolContext, 
        uint256 index1,
        uint256 index2
    ) internal pure returns (uint256 spotPrice) {
        // BPT index is not supported
        require(
            index1 != poolContext.bptIndex && index1 < poolContext.basePool.tokens.length
        ); /// @dev invalid token index
        require(
            index2 != poolContext.bptIndex && index2 < poolContext.basePool.tokens.length
        ); /// @dev invalid token index

        // Return 1 if token1 and token2 are the same token
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

        spotPrice = StableMath._calcSpotPrice(
            oracleContext.ampParam, invariant, balanceX, balanceY
        );

        /// Apply secondary scale factor in reverse
        uint256 scaleFactor = poolContext.scalingFactors[index2] * BalancerConstants.BALANCER_PRECISION 
            / poolContext.scalingFactors[index1];
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / scaleFactor;

        // Convert precision back to 1e18 after downscaling by scaleFactor
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / (10**poolContext.basePool.decimals[index2]);
    }
}
