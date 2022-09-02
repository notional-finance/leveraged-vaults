// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StableOracleContext, TwoTokenPoolContext, StrategyContext} from "../../BalancerVaultTypes.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Errors} from "../../../../global/Errors.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {IPriceOracle} from "../../../../../interfaces/balancer/IPriceOracle.sol";
import {StableMath} from "./StableMath.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library Stable2TokenOracleMath {
    using TypeConvert for int256;
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

    function _checkPriceLimit(
        StrategyContext calldata strategyContext,
        TwoTokenPoolContext memory poolContext,
        uint256 poolPrice
    ) private view returns (bool) {
        (
            int256 answer, int256 decimals
        ) = strategyContext.tradingModule.getOraclePrice(poolContext.secondaryToken, poolContext.primaryToken);

        require(decimals == int256(BalancerConstants.BALANCER_PRECISION));

        uint256 oraclePairPrice = answer.toUint();
        uint256 lowerLimit = (oraclePairPrice * 
            (BalancerConstants.VAULT_PERCENT_BASIS - strategyContext.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            BalancerConstants.VAULT_PERCENT_BASIS;
        uint256 upperLimit = (oraclePairPrice * 
            (BalancerConstants.VAULT_PERCENT_BASIS + strategyContext.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            BalancerConstants.VAULT_PERCENT_BASIS;

        if (poolPrice < lowerLimit || upperLimit < poolPrice) {
            revert Errors.InvalidPrice(oraclePairPrice, poolPrice);
        }
    }

    /// @notice calculates the expected min exit amounts for a given BPT amount
    function _getMinExitAmounts(
        StableOracleContext calldata oracleContext,
        TwoTokenPoolContext calldata poolContext,
        StrategyContext calldata strategyContext,
        uint256 bptAmount
    ) internal view returns (uint256 minPrimary, uint256 minSecondary) {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        // Validate the spot price to make sure the pool is not being manipulated
        uint256 spotPrice = _getSpotPrice(oracleContext, poolContext, 0);
        _checkPriceLimit(strategyContext, poolContext, spotPrice);

        // min amounts are calculated based on the share of the Balancer pool with a small discount applied
        uint256 totalBPTSupply = poolContext.basePool.pool.totalSupply();
        minPrimary = (poolContext.primaryBalance * bptAmount * 
            strategyContext.vaultSettings.balancerPoolSlippageLimitPercent) / 
            (totalBPTSupply * uint256(BalancerConstants.VAULT_PERCENT_BASIS));
        minSecondary = (poolContext.secondaryBalance * bptAmount * 
            strategyContext.vaultSettings.balancerPoolSlippageLimitPercent) / 
            (totalBPTSupply * uint256(BalancerConstants.VAULT_PERCENT_BASIS));
    }

    function _validateSpotPriceAndPairPrice(
        StableOracleContext calldata oracleContext,
        TwoTokenPoolContext calldata poolContext,
        StrategyContext calldata strategyContext,
        uint256 primaryAmount, 
        uint256 secondaryAmount
    ) internal view {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        uint256 spotPrice = _getSpotPrice(oracleContext, poolContext, 0);
        _checkPriceLimit(strategyContext, poolContext, spotPrice);

        // We always validate in terms of the primary here so it is the first value in the _balances array
        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, StableMath._balances(primaryAmount, secondaryAmount), true // round up
        );

        /// @notice Balancer math functions expect all amounts to be in BALANCER_PRECISION
        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;
        uint256 secondaryPrecision = 10 ** poolContext.secondaryDecimals;
        primaryAmount = primaryAmount * BalancerConstants.BALANCER_PRECISION / primaryPrecision;
        secondaryAmount = secondaryAmount * BalancerConstants.BALANCER_PRECISION / secondaryPrecision;

        uint256 calculatedPairPrice = StableMath._calcSpotPrice({
            amplificationParameter: oracleContext.ampParam,
            invariant: invariant,
            balanceX: primaryAmount,
            balanceY: secondaryAmount
        });

        _checkPriceLimit(strategyContext, poolContext, calculatedPairPrice);
    }
}
