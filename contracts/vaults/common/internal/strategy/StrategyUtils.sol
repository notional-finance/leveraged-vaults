// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Errors} from "../../../../global/Errors.sol";
import {VaultConstants} from "../../VaultConstants.sol";
import {StrategyContext, TradeParams, StrategyVaultState} from "../../VaultTypes.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {TradeHandler} from "../../../../trading/TradeHandler.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {Constants} from "../../../../global/Constants.sol";
import {ITradingModule, Trade, TradeType} from "../../../../../interfaces/trading/ITradingModule.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {VaultStorage} from "../../VaultStorage.sol";

/**
 * @notice Strategy utility functions
 */
library StrategyUtils {
    using TradeHandler for Trade;
    using TokenUtils for IERC20;
    using TypeConvert for uint256;
    using VaultStorage for StrategyVaultState;

    /// @notice Checks the price against oracle price limits set by oraclePriceDeviationLimitPercent
    /// @param strategyContext strategy context
    /// @param oraclePrice oracle prie
    /// @param poolPrice spot price of the pool
    function _checkPriceLimit(
        StrategyContext memory strategyContext,
        uint256 oraclePrice,
        uint256 poolPrice
    ) internal pure {
        uint256 lowerLimit = (oraclePrice * 
            (VaultConstants.VAULT_PERCENT_BASIS - strategyContext.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            VaultConstants.VAULT_PERCENT_BASIS;
        uint256 upperLimit = (oraclePrice * 
            (VaultConstants.VAULT_PERCENT_BASIS + strategyContext.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            VaultConstants.VAULT_PERCENT_BASIS;

        if (poolPrice < lowerLimit || upperLimit < poolPrice) {
            revert Errors.InvalidPrice(oraclePrice, poolPrice);
        }
    }

    // /// @notice Converts strategy tokens to LP tokens
    // /// @param context strategy context
    // /// @param strategyTokenAmount amount of strategy tokens (vault shares)
    // /// @return poolClaim amount of pool tokens
    // function _convertStrategyTokensToPoolClaim(StrategyContext memory context, uint256 strategyTokenAmount)
    //     internal pure returns (uint256 poolClaim) {
    //     require(strategyTokenAmount <= context.vaultState.totalVaultSharesGlobal);
    //     if (context.vaultState.totalVaultSharesGlobal > 0) {
    //         poolClaim = (strategyTokenAmount * context.vaultState.totalPoolClaim) / context.vaultState.totalVaultSharesGlobal;
    //     }
    // }

    // /// @notice Converts LP tokens to strategy tokens
    // /// @param context strategy context
    // /// @param poolClaim amount of pool tokens
    // /// @return strategyTokenAmount amount of strategy tokens (vault shares)
    // function _convertPoolClaimToStrategyTokens(StrategyContext memory context, uint256 poolClaim)
    //     internal pure returns (uint256 strategyTokenAmount) {
    //     if (context.vaultState.totalPoolClaim == 0) {
    //         // Strategy tokens are in 8 decimal precision. Scale the minted amount according to pool claim precision.
    //         return (poolClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
    //             context.poolClaimPrecision;
    //     }

    //     // Pool claim in maturity is calculated before the new pool tokens are minted, so this calculation
    //     // is the tokens minted that will give the account a corresponding share of the new pool balance held.
    //     // The precision here will be the same as strategy token supply.
    //     strategyTokenAmount = (poolClaim * context.vaultState.totalVaultSharesGlobal) / context.vaultState.totalPoolClaim;
    // }

    function _executeDynamicSlippageTradeExactIn(
        ITradingModule tradingModule,
        TradeParams memory params,
        address sellToken,
        address buyToken,
        uint256 amount
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        // Can only do exact in trades
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE ||
            params.tradeType == TradeType.EXACT_IN_BATCH
        );
        // Ensure that the slippage percent is valid
        require(params.oracleSlippagePercentOrLimit <= Constants.SLIPPAGE_LIMIT_PRECISION);

        Trade memory trade = Trade(
            params.tradeType,
            sellToken,
            buyToken,
            amount,
            0,
            block.timestamp, // deadline
            params.exchangeData
        );

        (amountSold, amountBought) = trade._executeTradeWithDynamicSlippage(
            params.dexId, tradingModule, uint32(params.oracleSlippagePercentOrLimit)
        );
    }

    /// @notice Executes a trade with a static slippage limit, only used during
    /// reward reinvestment trades since oracles between the reward token and the
    /// purchased tokens may not exist.
    function _executeTradeWithStaticSlippage(
        ITradingModule tradingModule,
        TradeParams memory params,
        address sellToken,
        address buyToken,
        uint256 amount
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        /// @dev this function can only handle exact in trades
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE ||
            params.tradeType == TradeType.EXACT_IN_BATCH
        );

        // Sell residual secondary balance
        Trade memory trade = Trade(
            params.tradeType,
            sellToken,
            buyToken,
            amount,
            params.oracleSlippagePercentOrLimit,
            block.timestamp, // deadline
            params.exchangeData
        );

        // Execute trade using static slippage
        (amountSold, amountBought) = trade._executeTrade(params.dexId, tradingModule);
    }
}
