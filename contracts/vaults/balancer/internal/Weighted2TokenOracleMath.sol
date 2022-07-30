// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {WeightedOracleContext, TwoTokenPoolContext} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";

library Weighted2TokenOracleMath {
    /// @notice Gets the current spot price with a given token index, this is used to check against
    /// the oracle pair price to prevent front running
    /// @param oracleContext oracle context fields
    /// @param poolContext pool context fields
    /// @param tokenIndex index of the token to receive the spot price in
    /// @return spotPrice token spot price
    function _getSpotPrice(
        WeightedOracleContext memory oracleContext, 
        TwoTokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        // Prevents overflows, we don't expect tokens to be greater than 18 decimals, don't use
        // equal sign for minor gas optimization
        require(poolContext.primaryDecimals < 19); /// @dev primaryDecimals overflow
        require(poolContext.secondaryDecimals < 19); /// @dev secondaryDecimals overflow
        require(tokenIndex < 2); /// @dev invalid token index

        // prettier-ignore
        (/* */, uint256[] memory balances, /* */) 
            = BalancerUtils.BALANCER_VAULT.getPoolTokens(poolContext.basePool.poolId);

        // Normalize balances to 18 decimal places
        (balances[poolContext.primaryIndex], balances[poolContext.secondaryIndex]) = 
            BalancerUtils._normalizeBalances(
                balances[poolContext.primaryIndex], 
                poolContext.primaryDecimals, 
                balances[poolContext.secondaryIndex], 
                poolContext.secondaryDecimals
            );

        // Target token balance is the balance of the token we want the spot price in 
        uint256 targetTokenBalance = balances[tokenIndex];
        // Denominator balance is the balance of the other token
        uint256 otherBalance = balances[1 - tokenIndex];
        // Assign the weights based on the token index
        (uint256 targetTokenWeight, uint256 otherWeight) = 
            tokenIndex == poolContext.primaryIndex ?
                (oracleContext.weights[poolContext.primaryIndex], oracleContext.weights[poolContext.secondaryIndex]) :
                (oracleContext.weights[poolContext.secondaryIndex], oracleContext.weights[poolContext.primaryIndex]);

        // SpotPrice = (otherBalance * targetWeight * 1e18) / (targetBalance * otherWeight)
        spotPrice = (otherBalance * targetTokenWeight * BalancerUtils.BALANCER_PRECISION) / 
            (targetTokenBalance * otherWeight);
    }

    /// @notice Returns the optimal amount to borrow for the secondary token
    /// @param oracleContext oracle context variables
    /// @param poolContext oracle context variables
    /// @return secondaryAmount optimal amount of the secondary token to join the pool
    function _getOptimalSecondaryBorrowAmount(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount
    ) internal view returns (uint256 secondaryAmount) {
        // Prevents overflows, we don't expect tokens to be greater than 18 decimals, don't use
        // equal sign for minor gas optimization
        require(poolContext.primaryDecimals < 19); /// @dev primaryDecimals overflow
        require(poolContext.secondaryDecimals < 19); /// @dev secondaryDecimals overflow

        // Use the oracle price here rather than the spot price to prevent flash loan
        // manipulation (would force the user to join at a disadvantageous price). If
        // the pool is being manipulated away from the oracle price and this generates
        // excess slippage when joining, the user must specify a minBPT amount that will
        // cause the transaction to revert.
        uint256 pairPrice = BalancerUtils._getTimeWeightedOraclePrice(
            address(poolContext.basePool.pool),
            IPriceOracle.Variable.PAIR_PRICE,
            oracleContext.baseOracle.oracleWindowInSeconds
        );

        if (poolContext.primaryIndex == 0) {
            // If the primary index is the first token, invert the pair price
            pairPrice = BalancerUtils.BALANCER_PRECISION_SQUARED / pairPrice;
        }

        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;
        uint256 secondaryPrecision = 10 ** poolContext.secondaryDecimals;

        // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice) / PrimaryWeight
        // Also, we want to normalize to secondary token precision
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice * SecondaryPrecision) /
        //    (PrimaryWeight * PrimaryPrecision * BalancerPrecision[for PairPrice])
        secondaryAmount = 
            (primaryAmount * oracleContext.weights[poolContext.secondaryIndex] * pairPrice * secondaryPrecision) / 
            (oracleContext.weights[poolContext.primaryIndex] * primaryPrecision * BalancerUtils.BALANCER_PRECISION);
    }
}
