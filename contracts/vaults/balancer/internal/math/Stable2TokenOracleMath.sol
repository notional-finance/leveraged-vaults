// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StableOracleContext, TwoTokenPoolContext} from "../../BalancerVaultTypes.sol";
import {Constants} from "../../../../global/Constants.sol";
import {Errors} from "../../../../global/Errors.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {IPriceOracle} from "../../../../../interfaces/balancer/IPriceOracle.sol";
import {StableMath} from "./StableMath.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library Stable2TokenOracleMath {
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

        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, _balances(balanceX, balanceY), true // round up
        );

        uint256 a = (oracleContext.ampParam * 2) / StableMath._AMP_PRECISION;
        uint256 b = invariant * a - invariant;

        uint256 axy2 = StableMath.mulDown(a * 2 * balanceX, balanceY); // n = 2

        // dx = a.x.y.2 + a.y^2 - b.y
        uint256 derivativeX = axy2 + StableMath.mulDown(a * balanceY, balanceY) - (StableMath.mulDown(b, balanceY));

        // dy = a.x.y.2 + a.x^2 - b.x
        uint256 derivativeY = axy2 + StableMath.mulDown(a * balanceX, balanceX) - (StableMath.mulDown(b, balanceX));

        // The rounding direction is irrelevant as we're about to introduce a much larger error when converting to log
        // space. We use `divUp` as it prevents the result from being zero, which would make the logarithm revert. A
        // result of zero is therefore only possible with zero balances, which are prevented via other means.
        spotPrice = StableMath.divUpFixed(derivativeX, derivativeY);
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
        // TODO: implement this
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
