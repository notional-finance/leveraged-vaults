// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {TwoTokenPoolContext, OracleContext, PoolParams} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";

library TwoTokenPoolUtils {
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    error InvalidMinAmounts(uint256 pairPrice, uint256 minPrimary, uint256 minSecondary);

    /// @notice Returns parameters for joining and exiting pool
    function _getPoolParams(
        TwoTokenPoolContext memory context,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        bool isJoin
    ) internal pure returns (PoolParams memory) {
        IAsset[] memory assets = new IAsset[](2);
        assets[context.primaryIndex] = IAsset(context.primaryToken);
        uint8 secondaryIndex;
        unchecked { secondaryIndex = 1 - context.primaryIndex; }
        assets[secondaryIndex] = IAsset(context.secondaryToken);

        uint256[] memory amounts = new uint256[](2);
        amounts[context.primaryIndex] = primaryAmount;
        amounts[secondaryIndex] = secondaryAmount;

        uint256 msgValue;
        if (isJoin && assets[context.primaryIndex] == IAsset(Constants.ETH_ADDRESS)) {
            msgValue = amounts[context.primaryIndex];
        }

        return PoolParams(assets, amounts, msgValue);
    }

    /// @notice Gets the oracle price pair price between two tokens using a weighted
    /// average between a chainlink oracle and the balancer TWAP oracle.
    /// @param poolContext oracle context variables
    /// @param oracleContext oracle context variables
    /// @param tradingModule address of the trading module
    /// @return oraclePairPrice oracle price for the pair in 18 decimals
    function _getOraclePairPrice(
        TwoTokenPoolContext memory poolContext,
        OracleContext memory oracleContext, 
        ITradingModule tradingModule
    ) internal view returns (uint256 oraclePairPrice) {
        // NOTE: this balancer price is denominated in 18 decimal places
        uint256 balancerWeightedPrice;
        if (oracleContext.balancerOracleWeight > 0) {
            uint256 balancerPrice = BalancerUtils._getTimeWeightedOraclePrice(
                address(poolContext.baseContext.pool),
                IPriceOracle.Variable.PAIR_PRICE,
                oracleContext.oracleWindowInSeconds
            );

            if (poolContext.primaryIndex == 1) {
                // If the primary index is the second token, we need to invert
                // the balancer price.
                balancerPrice = BalancerUtils.BALANCER_PRECISION_SQUARED / balancerPrice;
            }

            balancerWeightedPrice = balancerPrice * oracleContext.balancerOracleWeight;
        }

        uint256 chainlinkWeightedPrice;
        if (oracleContext.balancerOracleWeight < BalancerUtils.BALANCER_ORACLE_WEIGHT_PRECISION) {
            (int256 rate, int256 decimals) = tradingModule.getOraclePrice(
                poolContext.primaryToken, poolContext.secondaryToken
            );
            require(rate > 0);
            require(decimals >= 0);

            if (uint256(decimals) != BalancerUtils.BALANCER_PRECISION) {
                rate = (rate * int256(BalancerUtils.BALANCER_PRECISION)) / decimals;
            }

            // No overflow in rate conversion, checked above
            chainlinkWeightedPrice = uint256(rate) * 
                (BalancerUtils.BALANCER_ORACLE_WEIGHT_PRECISION - oracleContext.balancerOracleWeight);
        }

        oraclePairPrice = (balancerWeightedPrice + chainlinkWeightedPrice) / 
            BalancerUtils.BALANCER_ORACLE_WEIGHT_PRECISION;
    }

    /// @notice Validates the min Balancer exit amounts against the price oracle.
    /// These values are passed in as parameters. So, we must validate them.
    function _validateMinExitAmounts(
        TwoTokenPoolContext memory poolContext,
        OracleContext memory oracleContext,
        ITradingModule tradingModule,
        uint256 minPrimary,
        uint256 minSecondary
    ) internal view {
        (uint256 normalizedPrimary, uint256 normalizedSecondary) = BalancerUtils._normalizeBalances(
            minPrimary, poolContext.primaryDecimals, minSecondary, poolContext.secondaryDecimals
        );
        uint256 pairPrice = poolContext._getOraclePairPrice(oracleContext, tradingModule);
        uint256 calculatedPairPrice = normalizedSecondary * BalancerUtils.BALANCER_PRECISION / 
            normalizedPrimary;

        uint256 lowerLimit = (pairPrice * Constants.MIN_EXIT_AMOUNTS_LOWER_LIMIT) / 100;
        uint256 upperLimit = (pairPrice * Constants.MIN_EXIT_AMOUNTS_UPPER_LIMIT) / 100;
        if (calculatedPairPrice < lowerLimit || upperLimit < calculatedPairPrice) {
            revert InvalidMinAmounts(pairPrice, minPrimary, minSecondary);
        }
    }
}
