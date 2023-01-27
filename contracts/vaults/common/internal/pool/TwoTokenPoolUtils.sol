// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TwoTokenPoolContext, StrategyContext, DepositTradeParams} from "../../VaultTypes.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library TwoTokenPoolUtils {
    using StrategyUtils for StrategyContext;

    /// @notice Gets the oracle price pair price between two tokens using a weighted
    /// average between a chainlink oracle and the balancer TWAP oracle.
    /// @param poolContext oracle context variables
    /// @param strategyContext strategy context variables
    /// @return oraclePairPrice oracle price for the pair in 18 decimals
    function _getOraclePairPrice(
        TwoTokenPoolContext memory poolContext,
        StrategyContext memory strategyContext
    ) internal view returns (uint256 oraclePairPrice) {
        (int256 rate, int256 decimals) = strategyContext.tradingModule.getOraclePrice(
            poolContext.primaryToken, poolContext.secondaryToken
        );
        require(rate > 0);
        require(decimals >= 0);

        if (uint256(decimals) != strategyContext.poolClaimPrecision) {
            rate = (rate * int256(strategyContext.poolClaimPrecision)) / decimals;
        }

        // No overflow in rate conversion, checked above
        oraclePairPrice = uint256(rate);
    }

    function _getTimeWeightedPrimaryBalance(
        TwoTokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        uint256 poolClaim,
        uint256 oraclePrice,
        uint256 spotPrice
    ) internal view returns (uint256 primaryAmount) {
        // Make sure spot price is within oracleDeviationLimit of pairPrice
        strategyContext._checkPriceLimit(oraclePrice, spotPrice);
        
        // Get shares of primary and secondary balances with the provided bptAmount
        uint256 totalSupply = poolContext.poolToken.totalSupply();
        uint256 primaryBalance = poolContext.primaryBalance * poolClaim / totalSupply;
        uint256 secondaryBalance = poolContext.secondaryBalance * poolClaim / totalSupply;

        // Value the secondary balance in terms of the primary token using the oraclePairPrice
        uint256 secondaryAmountInPrimary = secondaryBalance * strategyContext.poolClaimPrecision / oraclePrice;

        // Make sure primaryAmount is reported in primaryPrecision
        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;
        primaryAmount = (primaryBalance + secondaryAmountInPrimary) * primaryPrecision / strategyContext.poolClaimPrecision;
    }

    /// @notice Trade primary currency for secondary if the trade is specified
    function _tradePrimaryForSecondary(
        TwoTokenPoolContext memory poolContext,
        StrategyContext memory strategyContext,
        bytes memory data
    ) internal returns (uint256 primarySold, uint256 secondaryBought) {
        (DepositTradeParams memory params) = abi.decode(data, (DepositTradeParams));

        (primarySold, secondaryBought) = StrategyUtils._executeTradeExactIn({
            params: params.tradeParams, 
            tradingModule: strategyContext.tradingModule, 
            sellToken: poolContext.primaryToken, 
            buyToken: poolContext.secondaryToken, 
            amount: params.tradeAmount,
            useDynamicSlippage: true
        });
    }
}
