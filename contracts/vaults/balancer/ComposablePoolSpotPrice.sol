// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Deployments} from "../../global/Deployments.sol";
import {StableMath} from "./math/StableMath.sol";
import {IComposablePool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IBalancerVault} from "../../../interfaces/balancer/IBalancerVault.sol";

contract ComposablePoolSpotPrice {
    uint256 internal constant BALANCER_PRECISION = 1e18;

    function getSpotPrices(
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

            spotPrices[i] = _calculateSpotPrice(
                ampParam, scalingFactors, balances, scaledPrimary, primaryIndex, i
            );
        }
    }

    function _calculateSpotPrice(
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