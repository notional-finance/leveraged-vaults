// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    TwoTokenPoolContext, 
    StrategyContext, 
    DepositTradeParams, 
    TradeParams,
    SingleSidedRewardTradeParams,
    Proportional2TokenRewardTradeParams,
    RedeemParams
} from "../../VaultTypes.sol";
import {VaultConstants} from "../../VaultConstants.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {Errors} from "../../../../global/Errors.sol";
import {ITradingModule, DexId} from "../../../../../interfaces/trading/ITradingModule.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";

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
        
        // Get shares of primary and secondary balances with the provided poolClaim
        uint256 totalSupply = poolContext.poolToken.totalSupply();
        uint256 primaryBalance = poolContext.primaryBalance * poolClaim / totalSupply;
        uint256 secondaryBalance = poolContext.secondaryBalance * poolClaim / totalSupply;
        
        // Scale secondary balance to primaryPrecision
        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;
        uint256 secondaryPrecision = 10 ** poolContext.secondaryDecimals;
        secondaryBalance = secondaryBalance * primaryPrecision / secondaryPrecision;

        // Value the secondary balance in terms of the primary token using the oraclePairPrice
        uint256 secondaryAmountInPrimary = secondaryBalance * strategyContext.poolClaimPrecision / oraclePrice;

        primaryAmount = primaryBalance + secondaryAmountInPrimary;
    }

    /// @notice Trade primary cur
    function _validateTrades(
        SingleSidedRewardTradeParams memory primaryTrade,
        SingleSidedRewardTradeParams memory secondaryTrade,
        address primaryToken,
        address secondaryToken,
        address poolToken
    ) private pure {
        // Make sure we are not selling one of the core tokens
        if (primaryTrade.sellToken == primaryToken || 
            primaryTrade.sellToken == secondaryToken || 
            primaryTrade.sellToken == poolToken
        ) {
            revert Errors.InvalidRewardToken(primaryTrade.sellToken);
        }
        if (secondaryTrade.sellToken != primaryTrade.sellToken) {
            revert Errors.InvalidRewardToken(secondaryTrade.sellToken);
        }
        if (primaryTrade.buyToken != primaryToken) {
            revert Errors.InvalidRewardToken(primaryTrade.buyToken);
        }
        if (secondaryTrade.buyToken != secondaryToken) {
            revert Errors.InvalidRewardToken(secondaryTrade.buyToken);
        }
    }
}
