// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import {IPriceOracle} from "../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {BalancerUtils} from "./BalancerUtils.sol";

// @audit since this is actually balancer specific, maybe we should make a sub folder in vaults/Balancer
// and just put this in there instead?
// @audit if this library and balancer utils are both external, why not combine them into a single
// library so we only have to deploy one contract?
library OracleHelper {
    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param bptAmount BPT amount
    /// @return primaryBalance primary token balance
    function getTimeWeightedPrimaryBalance(
        address pool,
        uint256 oracleWindowInSeconds,
        uint8 primaryindex, // @audit this should be camelCase
        uint256 primaryWeight,
        uint256 secondaryWeight,
        // @audit primary decimals should be typed as uint8 or they can potentially overflow in the exponent
        uint256 primaryDecimals,
        uint256 bptAmount
    ) external view returns (uint256) {
        // Gets the BPT token price
        // @audit combine these into a single library to avoid cross library calls like this
        uint256 bptPrice = BalancerUtils.getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.BPT_PRICE,
            oracleWindowInSeconds
        );

        // The first token in the BPT pool is the primary token.
        // Since bptPrice is always denominated in the first token,
        // Both bptPrice and bptAmount are in 1e18
        // underlyingValue = bptPrice * bptAmount / 1e18
        if (primaryindex == 0) {
            uint256 primaryAmount = (bptPrice * bptAmount) / 1e18;

            // Normalize precision to primary precision
            return (primaryAmount * primaryDecimals) / 1e18;
        }
        // @audit use an else here for readability since it's not obvious that
        // the method will return in the if clause above

        // The second token in the BPT pool is the primary token.
        // In this case, we need to convert secondaryTokenValue
        // to underlyingValue using the pairPrice.
        // Both bptPrice and bptAmount are in 1e18
        uint256 secondaryAmount = (bptPrice * bptAmount) / 1e18;

        // Gets the pair price
        // @audit another cross contract call, probably unnecessary
        uint256 pairPrice = BalancerUtils.getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // PairPrice =  (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
        // (SecondaryAmount / SecondaryWeight) / PairPrice = (PrimaryAmount / PrimaryWeight)
        // PrimaryAmount = (SecondaryAmount / SecondaryWeight) / PairPrice * PrimaryWeight
        // @audit this can be further simplified to, use this formula instead because it uses
        // less division between steps and therefore will result in less precision loss.
        // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)

        // Calculate weighted secondary amount
        secondaryAmount = ((secondaryAmount * 1e18) / secondaryWeight);

        // Calculate primary amount using pair price
        uint256 primaryAmount = ((secondaryAmount * 1e18) / pairPrice);

        // Calculate secondary amount (precision is still 1e18)
        primaryAmount = (primaryAmount * primaryWeight) / 1e18;

        // Normalize precision to secondary precision (Balancer uses 1e18)
        return (primaryAmount * 10**primaryDecimals) / 1e18;
    }

    // @audit this should be calculated in the method above and returned to reduce gas
    function getPairPrice(
        address pool,
        address vault,
        bytes32 poolId,
        address tradingModule,
        uint256 oracleWindowInSeconds,
        uint256 balancerOracleWeight
    ) external view returns (uint256) {
        // @audit this should only be called if balancerOracleWeight > 0
        uint256 balancerPrice = BalancerUtils.getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = IBalancerVault(vault).getPoolTokens(poolId);

        // @audit this should only be called if balancerOracleWeight < 1e8
        (int256 chainlinkPrice, int256 decimals) = ITradingModule(
            tradingModule
        ).getOraclePrice(tokens[1], tokens[0]);

        // @audit zero may be a valid price
        require(chainlinkPrice >= 0); /// @dev Chainlink rate error
        require(decimals >= 0); /// @dev Chainlink decimals error

        // Normalize price to 18 decimals
        // @audit this should only be done if decimals != 1e18
        chainlinkPrice = (chainlinkPrice * 1e18) / decimals;

        // @audit 1e8 should be a constant with a defined name here
        // @audit for readability these should be split into two named variables
        return
            (balancerPrice * balancerOracleWeight) /
            1e8 +
            (uint256(chainlinkPrice) * (1e8 - balancerOracleWeight)) /
            1e8;
    }

    function getOptimalSecondaryBorrowAmount(
        address pool,
        uint256 oracleWindowInSeconds,
        uint8 primaryindex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        // @audit primary decimals and secondary decimals should be typed as uint8 or they
        // can potentially overflow in the exponent
        uint256 primaryDecimals,
        uint256 secondaryDecimals,
        uint256 primaryAmount
    )
        external
        view
        returns (uint256 secondaryAmount)
    {
        // Gets the PAIR price
        uint256 pairPrice = BalancerUtils.getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // @audit these two formulas can be further simplified to the following which uses
        // less division between steps and therefore will result in less precision loss.
        // PrimaryAmount = (SecondaryAmount * PrimaryWeight) / (SecondaryWeight * PairPrice)
        // SecondaryAmount = (PrimaryAmount * SecondaryWeight * PairPrice) / PrimaryWeight

        // Calculate weighted primary amount
        primaryAmount = ((primaryAmount * 1e18) / primaryWeight);

        // Calculate price adjusted primary amount, price is always in 1e18
        // Since price is always expressed as the price of the second token in units of the
        // first token, we need to invert the math if the second token is the primary token
        if (primaryindex == 0) {
            // PairPrice = (PrimaryAmount / PrimaryWeight) / (SecondaryAmount / SecondaryWeight)
            // SecondaryAmount = (PrimaryAmount / PrimaryWeight) / PairPrice * SecondaryWeight
            primaryAmount = ((primaryAmount * 1e18) / pairPrice);
        } else {
            // PairPrice = (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
            // SecondaryAmount = (PrimaryAmount / PrimaryWeight) * PairPrice * SecondaryWeight
            primaryAmount = ((primaryAmount * pairPrice) / 1e18);
        }

        // Calculate secondary amount (precision is still 1e18)
        secondaryAmount = (primaryAmount * secondaryWeight) / 1e18;

        // Normalize precision to secondary precision
        secondaryAmount =
            (secondaryAmount * 10**secondaryDecimals) /
            10**primaryDecimals;
    }
}
