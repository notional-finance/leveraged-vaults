// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {WeightedOracleContext, TwoTokenPoolContext} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "../BalancerUtils.sol";

library Weighted2TokenOracleMath {
    /// @notice Gets the current spot price with a given token index, this is used to check against
    /// the oracle pair price to prevent front running
    /// @param oracleContext oracle context fields
    /// @param poolContext pool context fields
    /// @param tokenIndex index of the token to receive the spot price in
    /// @return spotPrice token spot price
    function getSpotPrice(
        WeightedOracleContext memory oracleContext, 
        TwoTokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        // Prevents overflows, we don't expect tokens to be greater than 18 decimals, don't use
        // equal sign for minor gas optimization
        require(poolContext.primaryDecimals < 19);
        require(poolContext.secondaryDecimals < 19);
        require(tokenIndex < 2);

        // prettier-ignore
        (/* */, uint256[] memory balances, /* */) 
            = BalancerUtils.BALANCER_VAULT.getPoolTokens(poolContext.baseContext.poolId);

        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - poolContext.primaryIndex;
        }

        // Normalize balances to 18 decimal places
        (balances[poolContext.primaryIndex], balances[secondaryIndex]) = 
            BalancerUtils._normalizeBalances(
                balances[poolContext.primaryIndex], 
                poolContext.primaryDecimals, 
                balances[secondaryIndex], 
                poolContext.secondaryDecimals
            );

        // Target token balance is the balance of the token we want the spot price in 
        uint256 targetTokenBalance = balances[tokenIndex];
        // Denominator balance is the balance of the other token
        uint256 otherBalance = balances[1 - tokenIndex];
        // Assign the weights based on the token index
        (uint256 targetTokenWeight, uint256 otherWeight) = 
            tokenIndex == poolContext.primaryIndex ?
                (oracleContext.primaryWeight, oracleContext.secondaryWeight) :
                (oracleContext.secondaryWeight, oracleContext.primaryWeight);

        // SpotPrice = (otherBalance * targetWeight * 1e18) / (targetBalance * otherWeight)
        spotPrice = (otherBalance * targetTokenWeight * BalancerUtils.BALANCER_PRECISION) / 
            (targetTokenBalance * otherWeight);
    }
}
