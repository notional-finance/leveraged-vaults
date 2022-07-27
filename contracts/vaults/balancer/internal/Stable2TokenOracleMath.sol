// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Stable2TokenOracleContext, TwoTokenPoolContext} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";

library Stable2TokenOracleMath {
    using Stable2TokenOracleMath for Stable2TokenOracleContext;

    error InvalidSpotPrice(uint256 oraclePrice, uint256 spotPrice);
    error CalculationDidNotConverge();

    uint256 internal constant _AMP_PRECISION = 1e3;
    uint256 internal constant ONE = 1e18; // 18 decimal places

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 product = a * b;
        require(a == 0 || product / a == b);
        return product / ONE;
    }

    function div(
        uint256 a,
        uint256 b,
        bool roundUp
    ) internal pure returns (uint256) {
        return roundUp ? divUp(a, b) : divDown(a, b);
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        } else {
            return 1 + (a - 1) / b;
        }
    }

    function divUpFixed(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        } else {
            uint256 aInflated = a * ONE;

            // The traditional divUp formula is:
            // divUp(x, y) := (x + y - 1) / y
            // To avoid intermediate overflow in the addition, we distribute the division and get:
            // divUp(x, y) := (x - 1) / y + 1
            // Note that this requires x != 0, which we already tested for.

            return ((aInflated - 1) / b) + 1;
        }
    }

    // Note on unchecked arithmetic:
    // This contract performs a large number of additions, subtractions, multiplications and divisions, often inside
    // loops. Since many of these operations are gas-sensitive (as they happen e.g. during a swap), it is important to
    // not make any unnecessary checks. We rely on a set of invariants to avoid having to use checked arithmetic (the
    // Math library), including:
    //  - the number of tokens is bounded by _MAX_STABLE_TOKENS
    //  - the amplification parameter is bounded by _MAX_AMP * _AMP_PRECISION, which fits in 23 bits
    //  - the token balances are bounded by 2^112 (guaranteed by the Vault) times 1e18 (the maximum scaling factor),
    //    which fits in 172 bits
    //
    // This means e.g. we can safely multiply a balance by the amplification parameter without worrying about overflow.

    // Computes the invariant given the current balances, using the Newton-Raphson approximation.
    // The amplification parameter equals: A n^(n-1)
    function _calculateInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances,
        bool roundUp
    ) internal pure returns (uint256) {
        /**********************************************************************************************
        // invariant                                                                                 //
        // D = invariant                                                  D^(n+1)                    //
        // A = amplification coefficient      A  n^n S + D = A D n^n + -----------                   //
        // S = sum of balances                                             n^n P                     //
        // P = product of balances                                                                   //
        // n = number of tokens                                                                      //
        *********x************************************************************************************/

        // We support rounding up or down.

        uint256 sum = 0;
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; i++) {
            sum += balances[i];
        }
        if (sum == 0) {
            return 0;
        }

        uint256 prevInvariant = 0;
        uint256 invariant = sum;
        uint256 ampTimesTotal = amplificationParameter * numTokens;

        for (uint256 i = 0; i < 255; i++) {
            uint256 P_D = balances[0] * numTokens;
            for (uint256 j = 1; j < numTokens; j++) {
                P_D = div(P_D * balances[j] * numTokens, invariant, roundUp);
            }
            prevInvariant = invariant;
            invariant = div(
                (numTokens * invariant * invariant) + div(ampTimesTotal * sum * P_D, _AMP_PRECISION, roundUp),
                ((numTokens + 1) * invariant) + div((ampTimesTotal - _AMP_PRECISION) * P_D, _AMP_PRECISION, !roundUp),
                roundUp
            );

            if (invariant > prevInvariant) {
                if (invariant - prevInvariant <= 1) {
                    return invariant;
                }
            } else if (prevInvariant - invariant <= 1) {
                return invariant;
            }
        }

        revert CalculationDidNotConverge();
    }

    function _getSpotPrice(
        Stable2TokenOracleContext memory oracleContext, 
        TwoTokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        // Prevents overflows, we don't expect tokens to be greater than 18 decimals, don't use
        // equal sign for minor gas optimization
        require(poolContext.primaryDecimals < 19); /// @dev primaryDecimals overflow
        require(poolContext.secondaryDecimals < 19); /// @dev secondaryDecimals overflow
        require(tokenIndex < 2); /// @dev invalid token index

        /**************************************************************************************************************
        //                                                                                                           //
        //                             2.a.x.y + a.y^2 + b.y                                                         //
        // spot price Y/X = - dx/dy = -----------------------                                                        //
        //                             2.a.x.y + a.x^2 + b.x                                                         //
        //                                                                                                           //
        // n = 2                                                                                                     //
        // a = amp param * n                                                                                         //
        // b = D + a.(S - D)                                                                                         //
        // D = invariant                                                                                             //
        // S = sum of balances but x,y = 0 since x  and y are the only tokens                                        //
        **************************************************************************************************************/
        (uint256 balanceX, uint256 balanceY) = tokenIndex == 0 ?
            (poolContext.primaryBalance, poolContext.secondaryBalance) :
            (poolContext.secondaryBalance, poolContext.primaryBalance);

        uint256 invariant = _calculateInvariant(
            oracleContext.ampParam, _balances(balanceX, balanceY), true // round up
        );

        uint256 a = (oracleContext.ampParam * 2) / _AMP_PRECISION;
        uint256 b = invariant * a - invariant;

        uint256 axy2 = mulDown(a * 2 * balanceX, balanceY); // n = 2

        // dx = a.x.y.2 + a.y^2 - b.y
        uint256 derivativeX = axy2 + mulDown(a * balanceY, balanceY) - (mulDown(b, balanceY));

        // dy = a.x.y.2 + a.x^2 - b.x
        uint256 derivativeY = axy2 + mulDown(a * balanceX, balanceX) - (mulDown(b, balanceX));

        // The rounding direction is irrelevant as we're about to introduce a much larger error when converting to log
        // space. We use `divUp` as it prevents the result from being zero, which would make the logarithm revert. A
        // result of zero is therefore only possible with zero balances, which are prevented via other means.
        spotPrice = divUpFixed(derivativeX, derivativeY);
    }

    function _balances(uint256 balanceX, uint256 balanceY) private pure returns (uint256[] memory balances) {
        balances = new uint256[](2);
        balances[0] = balanceX;
        balances[1] = balanceY;
    }

    /// @notice Returns the optimal amount to borrow for the secondary token
    /// @param oracleContext oracle context variables
    /// @param poolContext oracle context variables
    /// @return secondaryAmount optimal amount of the secondary token to join the pool
    function _getOptimalSecondaryBorrowAmount(
        Stable2TokenOracleContext memory oracleContext,
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

        uint256 lowerLimit = (oraclePrice * Constants.SPOT_PRICE_LOWER_LIMIT) / 100;
        uint256 upperLimit = (oraclePrice * Constants.SPOT_PRICE_UPPER_LIMIT) / 100;

        // Check spot price against oracle price to make sure it hasn't been manipulated
        if (spotPrice < lowerLimit || upperLimit < spotPrice) {
            revert InvalidSpotPrice(oraclePrice, spotPrice);
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
}
