// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {TwoTokenPoolContext, OracleContext, PoolParams} from "../../BalancerVaultTypes.sol";
import {Constants} from "../../../../global/Constants.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Errors} from "../../../../global/Errors.sol";
import {IAsset} from "../../../../../interfaces/balancer/IBalancerVault.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";
import {IPriceOracle} from "../../../../../interfaces/balancer/IPriceOracle.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";

library TwoTokenPoolUtils {
    using TokenUtils for IERC20;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    /// @notice Returns parameters for joining and exiting Balancer pools
    function _getPoolParams(
        TwoTokenPoolContext memory context,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        bool isJoin
    ) internal pure returns (PoolParams memory) {
        IAsset[] memory assets = new IAsset[](2);
        assets[context.primaryIndex] = IAsset(context.primaryToken);
        assets[context.secondaryIndex] = IAsset(context.secondaryToken);

        uint256[] memory amounts = new uint256[](2);
        amounts[context.primaryIndex] = primaryAmount;
        amounts[context.secondaryIndex] = secondaryAmount;

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
                address(poolContext.basePool.pool),
                IPriceOracle.Variable.PAIR_PRICE,
                oracleContext.oracleWindowInSeconds
            );

            if (poolContext.primaryIndex == 1) {
                // If the primary index is the second token, we need to invert
                // the balancer price.
                balancerPrice = BalancerConstants.BALANCER_PRECISION_SQUARED / balancerPrice;
            }

            balancerWeightedPrice = balancerPrice * oracleContext.balancerOracleWeight;
        }

        uint256 chainlinkWeightedPrice;
        if (oracleContext.balancerOracleWeight < BalancerConstants.BALANCER_ORACLE_WEIGHT_PRECISION) {
            (int256 rate, int256 decimals) = tradingModule.getOraclePrice(
                poolContext.primaryToken, poolContext.secondaryToken
            );
            require(rate > 0);
            require(decimals >= 0);

            if (uint256(decimals) != BalancerConstants.BALANCER_PRECISION) {
                rate = (rate * int256(BalancerConstants.BALANCER_PRECISION)) / decimals;
            }

            // No overflow in rate conversion, checked above
            chainlinkWeightedPrice = uint256(rate) * 
                (BalancerConstants.BALANCER_ORACLE_WEIGHT_PRECISION - oracleContext.balancerOracleWeight);
        }

        oraclePairPrice = (balancerWeightedPrice + chainlinkWeightedPrice) / 
            BalancerConstants.BALANCER_ORACLE_WEIGHT_PRECISION;
    }

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param poolContext pool context variables
    /// @param oracleContext oracle context variables
    /// @param bptAmount amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function _getTimeWeightedPrimaryBalance(
        TwoTokenPoolContext memory poolContext,
        OracleContext memory oracleContext,
        uint256 bptAmount
    ) internal view returns (uint256 primaryAmount) {
        // Gets the BPT token price denominated in token index = 0
        uint256 bptPrice = BalancerUtils._getTimeWeightedOraclePrice(
            address(poolContext.basePool.pool),
            IPriceOracle.Variable.BPT_PRICE,
            oracleContext.oracleWindowInSeconds
        );

        // Gets the pair price
        uint256 pairPrice = BalancerUtils._getTimeWeightedOraclePrice(
            address(poolContext.basePool.pool),
            IPriceOracle.Variable.PAIR_PRICE,
            oracleContext.oracleWindowInSeconds
        );

        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;

        if (poolContext.primaryIndex == 0) {
            // Since bptPrice is always denominated in the first token, we can just multiply by
            // the amount in this case. Both bptPrice and bptAmount are in 1e18 but we need to scale
            // this back to the primary token's native precision.
            // underlyingValue = (bptPrice * bptAmount * primaryPrecision) / (1e18 * 1e18)
            primaryAmount = (bptPrice * bptAmount * primaryPrecision) / 
                BalancerConstants.BALANCER_PRECISION_SQUARED;
        } else {
            // The second token in the BPT pool is the price that we want to get. In this case, we need to
            // convert secondaryTokenValue to underlyingValue using the pairPrice.
            // Both bptPrice and bptAmount are in 1e18
            uint256 secondaryAmount = (bptPrice * bptAmount) / BalancerConstants.BALANCER_PRECISION;

            // And then normalizing to primary token precision we add:
            // PrimaryAmount = (SecondaryAmount * primaryPrecision) / PairPrice
            primaryAmount = (secondaryAmount * primaryPrecision) / pairPrice;
        }
    }

    function _approveBalancerTokens(TwoTokenPoolContext memory poolContext, address bptSpender) internal {
        IERC20(poolContext.primaryToken).checkApprove(address(BalancerConstants.BALANCER_VAULT), type(uint256).max);
        IERC20(poolContext.secondaryToken).checkApprove(address(BalancerConstants.BALANCER_VAULT), type(uint256).max);
        // Allow BPT spender to pull BALANCER_POOL_TOKEN
        IERC20(address(poolContext.basePool.pool)).checkApprove(bptSpender, type(uint256).max);
    }
}
