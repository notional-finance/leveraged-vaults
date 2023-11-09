// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/console.sol";
import {Deployments} from "../../global/Deployments.sol";
import {StableMath} from "./math/StableMath.sol";
import {IComposablePool, IWeightedPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IBalancerVault} from "../../../interfaces/balancer/IBalancerVault.sol";

/**
 * @notice External, singleton helper contract deployed to calculate spot prices for Balancer pools.
 * Currently supports Composable pools with any number of tokens and Weighted2Token pools.
 */
contract BalancerSpotPrice {
    uint256 internal constant BALANCER_PRECISION = 1e18;

    /// @notice Returns the weighted pool spot price and balances. Only the spot price on the
    /// secondary token is returned.
    function getWeightedSpotPrices(
        bytes32 poolId,
        address poolAddress,
        uint256 primaryIndex,
        uint8 primaryDecimals
    ) external view returns (uint256[] memory balances, uint256[] memory spotPrices) {
        (/* */, balances, /* */) = Deployments.BALANCER_VAULT.getPoolTokens(poolId);
        // Only two token pools are supported
        require(balances.length == 2);
        spotPrices = new uint256[](2);

        uint256[] memory weights = IWeightedPool(poolAddress).getNormalizedWeights();

        // Spot price calculation is specified at the link below. Do not account for swap fees
        // because we're using this price to compare to the oracle price and adding swap fees
        // would unnecessarily increase the price deviation.
        // https://docs.balancer.fi/reference/math/weighted-math.html#typescript
        // secondaryBalance * primaryWeight * primaryDecimals 
        // --------------------------------------------------- 
        //          primaryBalance * secondaryWeight
        uint256 secondaryIndex = 1 - primaryIndex;

        // There is a chance of a uint256 overflow if the balances[secondaryIndex] > 10**36
        uint256 numerator = balances[secondaryIndex] * weights[primaryIndex] * (10 ** primaryDecimals);
        uint256 denominator = balances[primaryIndex] * weights[secondaryIndex];
        spotPrices[secondaryIndex] = numerator / denominator;
    }

    /// @notice Returns the composable pool spot price and balances. Pool token spot
    /// prices are not returned, pool token balance is returned.
    function getComposableSpotPrices(
        bytes32 poolId,
        address poolAddress,
        uint256 primaryIndex
    ) external view returns (uint256[] memory balances, uint256[] memory spotPrices) {
        address[] memory tokens;
        (tokens, balances, /* */) = Deployments.BALANCER_VAULT.getPoolTokens(poolId);
        uint256[] memory scalingFactors = IComposablePool(poolAddress).getScalingFactors();

        (
            uint256 ampParam,
            /* bool isUpdating */,
            uint256 precision
        ) = IComposablePool(poolAddress).getAmplificationParameter();
        require(precision == StableMath._AMP_PRECISION);

        // The primary index spot price is left as zero.
        spotPrices = new uint256[](tokens.length);
        uint256 scaledPrimary = balances[primaryIndex] * scalingFactors[primaryIndex] / BALANCER_PRECISION;
        for (uint256 i; i < tokens.length; i++) {
            if (i == primaryIndex) continue;
            if (tokens[i] == poolAddress) continue;

            spotPrices[i] = _calculateStableMathSpotPrice(
                ampParam, scalingFactors, balances, scaledPrimary, primaryIndex, i
            );
        }
    }

    function _calculateStableMathSpotPrice(
        uint256 ampParam,
        uint256[] memory scalingFactors,
        uint256[] memory balances,
        uint256 scaledPrimary,
        uint256 primaryIndex,
        uint256 index2
    ) internal pure returns (uint256 spotPrice) {
        // Apply scale factors
        uint256 secondary = balances[index2] * scalingFactors[index2] / BALANCER_PRECISION;

        uint256 invariant = StableMath._calculateInvariant(
            ampParam, StableMath._balances(scaledPrimary, secondary), true // round up
        );

        spotPrice = StableMath._calcSpotPrice(ampParam, invariant, scaledPrimary, secondary);

        // Remove scaling factors from spot price
        spotPrice = spotPrice * scalingFactors[primaryIndex] / scalingFactors[index2];
    }
}