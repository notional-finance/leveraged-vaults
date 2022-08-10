// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StableOracleContext, TwoTokenPoolContext} from "../../BalancerVaultTypes.sol";
import {Constants} from "../../../../global/Constants.sol";
import {Errors} from "../../../../global/Errors.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {IPriceOracle} from "../../../../../interfaces/balancer/IPriceOracle.sol";
import {StableMath} from "./StableMath.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library Stable2TokenOracleMath {
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using Stable2TokenOracleMath for StableOracleContext;

    function _getSpotPrice(
        StableOracleContext memory oracleContext, 
        TwoTokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        // Prevents overflows, we don't expect tokens to be greater than 18 decimals, don't use
        // equal sign for minor gas optimization
        require(poolContext.primaryDecimals < 19); /// @dev primaryDecimals overflow
        require(poolContext.secondaryDecimals < 19); /// @dev secondaryDecimals overflow
        require(tokenIndex < 2); /// @dev invalid token index

        (uint256 balanceX, uint256 balanceY) = tokenIndex == 0 ?
            (poolContext.primaryBalance, poolContext.secondaryBalance) :
            (poolContext.secondaryBalance, poolContext.primaryBalance);

        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, StableMath._balances(balanceX, balanceY), true // round up
        );

        spotPrice = StableMath._calcSpotPrice({
            amplificationParameter: oracleContext.ampParam,
            invariant: invariant,
            balanceX: balanceX,
            balanceY: balanceY
        });
    }

    /// @notice Returns the optimal amount to borrow for the secondary token
    /// @param oracleContext oracle context variables
    /// @param poolContext oracle context variables
    /// @return secondaryAmount optimal amount of the secondary token to join the pool
    function _getOptimalSecondaryBorrowAmount(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount
    ) internal view returns (uint256 secondaryAmount) {
        // Prevents overflows, we don't expect tokens to be greater than 18 decimals, don't use
        // equal sign for minor gas optimization
        require(poolContext.primaryDecimals < 19); /// @dev primaryDecimals overflow
        require(poolContext.secondaryDecimals < 19); /// @dev secondaryDecimals overflow

        uint256 oraclePrice = BalancerUtils._getTimeWeightedOraclePrice(
            address(poolContext.basePool.pool),
            IPriceOracle.Variable.PAIR_PRICE,
            oracleContext.baseOracle.oracleWindowInSeconds
        );

        uint256 spotPrice = oracleContext._getSpotPrice(poolContext, poolContext.secondaryIndex); 

        uint256 lowerLimit = (oraclePrice * Constants.META_STABLE_SPOT_PRICE_LOWER_LIMIT) / 100;
        uint256 upperLimit = (oraclePrice * Constants.META_STABLE_SPOT_PRICE_UPPER_LIMIT) / 100;

        // Check spot price against oracle price to make sure it hasn't been manipulated
        if (spotPrice < lowerLimit || upperLimit < spotPrice) {
            revert Errors.InvalidSpotPrice(oraclePrice, spotPrice);
        }
        
        // Secondary amount is calculated by matching the primary amount proportionally based
        // on the pool balances (verified against the oracle price above)
        // primaryChangePercent = primaryBalance + primaryAmount / primaryBalance
        // secondaryAmount = (primaryChangePercent - 1) * secondaryBalance
        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;
        uint256 change = ((poolContext.primaryBalance + primaryAmount) * primaryPrecision) / 
            poolContext.primaryBalance;
        secondaryAmount = (change - primaryPrecision) * poolContext.secondaryBalance / 
            primaryPrecision;
    }

    /// @notice Validates the Balancer join/exit amounts against the price oracle.
    /// These values are passed in as parameters. So, we must validate them.
    function _validatePairPrice(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        ITradingModule tradingModule,
        uint256 primaryAmount,
        uint256 secondaryAmount
    ) internal view {
        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, StableMath._balances(primaryAmount, secondaryAmount), true // round up
        );

        uint256 calculatedPairPrice = StableMath._calcSpotPrice({
            amplificationParameter: oracleContext.ampParam,
            invariant: invariant,
            balanceX: primaryAmount,
            balanceY: secondaryAmount
        });

        (
            int256 answer, int256 decimals
        ) = tradingModule.getOraclePrice(poolContext.secondaryToken, poolContext.primaryToken);

        require(decimals == BalancerUtils.BALANCER_PRECISION.toInt());

        uint256 oraclePairPrice = answer.toUint();

        uint256 lowerLimit = (oraclePairPrice * Constants.META_STABLE_PAIR_PRICE_LOWER_LIMIT) / 100;
        uint256 upperLimit = (oraclePairPrice * Constants.META_STABLE_PAIR_PRICE_UPPER_LIMIT) / 100;
        if (calculatedPairPrice < lowerLimit || upperLimit < calculatedPairPrice) {
            revert Errors.InvalidPairPrice(oraclePairPrice, calculatedPairPrice, primaryAmount, secondaryAmount);
        }
    }

    function _validateSpotPriceAndPairPrice(
        StableOracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        ITradingModule tradingModule,
        uint256 spotPrice,
        uint256 primaryAmount, 
        uint256 secondaryAmount
    ) internal view {
        // TODO: implement this
    }
}
