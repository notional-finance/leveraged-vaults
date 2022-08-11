// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {WeightedOracleContext, TwoTokenPoolContext} from "../../BalancerVaultTypes.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {Constants} from "../../../../global/Constants.sol";
import {Errors} from "../../../../global/Errors.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {TwoTokenPoolUtils} from "../pool/TwoTokenPoolUtils.sol";
import {IPriceOracle} from "../../../../../interfaces/balancer/IPriceOracle.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library Weighted2TokenOracleMath {
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

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

    function _validatePairPriceInternal(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 oraclePairPrice,
        uint256 primaryAmount,
        uint256 secondaryAmount
    ) private view {
        (uint256 normalizedPrimary, uint256 normalizedSecondary) = BalancerUtils._normalizeBalances(
            primaryAmount, poolContext.primaryDecimals, secondaryAmount, poolContext.secondaryDecimals
        );
        
        uint256 calculatedPairPrice = 
            (normalizedSecondary * oracleContext.weights[poolContext.primaryIndex] * BalancerUtils.BALANCER_PRECISION) / 
            (normalizedPrimary * oracleContext.weights[poolContext.secondaryIndex]);

        uint256 lowerLimit = (oraclePairPrice * Constants.WEIGHTED_PAIR_PRICE_LOWER_LIMIT) / 100;
        uint256 upperLimit = (oraclePairPrice * Constants.WEIGHTED_PAIR_PRICE_UPPER_LIMIT) / 100;
        if (calculatedPairPrice < lowerLimit || upperLimit < calculatedPairPrice) {
            revert Errors.InvalidPairPrice(oraclePairPrice, calculatedPairPrice, primaryAmount, secondaryAmount);
        }
    }

    /// @notice Validates the Balancer join/exit amounts against the price oracle.
    /// These values are passed in as parameters. So, we must validate them.
    function _validatePairPrice(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        ITradingModule tradingModule,
        uint256 primaryAmount,
        uint256 secondaryAmount
    ) internal view {
        uint256 pairPrice = poolContext._getOraclePairPrice(oracleContext.baseOracle, tradingModule);

        _validatePairPriceInternal({
            oracleContext: oracleContext,
            poolContext: poolContext,
            oraclePairPrice: pairPrice,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount      
        });
    }

    function _validateSpotPriceAndPairPrice(
        WeightedOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        ITradingModule tradingModule,
        uint256 spotPrice,
        uint256 primaryAmount, 
        uint256 secondaryAmount
    ) internal view {
        (
            int256 answer, int256 decimals
        ) = tradingModule.getOraclePrice(poolContext.secondaryToken, poolContext.primaryToken);

        require(decimals == BalancerUtils.BALANCER_PRECISION.toInt());

        uint256 oraclePrice = answer.toUint();
        uint256 lowerLimit = (oraclePrice * Constants.WEIGHTED_SPOT_PRICE_LOWER_LIMIT) / 100;
        uint256 upperLimit = (oraclePrice * Constants.WEIGHTED_SPOT_PRICE_UPPER_LIMIT) / 100;

        // Check spot price against oracle price to make sure it hasn't been manipulated
        if (spotPrice < lowerLimit || upperLimit < spotPrice) {
            revert Errors.InvalidSpotPrice(oraclePrice, spotPrice);
        }

        _validatePairPriceInternal({
            oracleContext: oracleContext,
            poolContext: poolContext,
            oraclePairPrice: oraclePrice,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount      
        });
    }
}
