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

    /// @notice Converts strategy tokens to LP tokens
    /// @param context strategy context
    /// @param strategyTokenAmount amount of strategy tokens (vault shares)
    /// @return poolClaim amount of pool tokens
    function _convertStrategyTokensToPoolClaim(StrategyContext memory context, uint256 strategyTokenAmount)
        internal pure returns (uint256 poolClaim) {
        require(strategyTokenAmount <= context.vaultState.totalVaultSharesGlobal);
        if (context.vaultState.totalVaultSharesGlobal > 0) {
            poolClaim = (strategyTokenAmount * context.vaultState.totalPoolClaim) / context.vaultState.totalVaultSharesGlobal;
        }
    }

    /// @notice Converts LP tokens to strategy tokens
    /// @param context strategy context
    /// @param poolClaim amount of pool tokens
    /// @return strategyTokenAmount amount of strategy tokens (vault shares)
    function _convertPoolClaimToStrategyTokens(StrategyContext memory context, uint256 poolClaim)
        internal pure returns (uint256 strategyTokenAmount) {
        if (context.vaultState.totalPoolClaim == 0) {
            // Strategy tokens are in 8 decimal precision. Scale the minted amount according to pool claim precision.
            return (poolClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                context.poolClaimPrecision;
        }

        // Pool claim in maturity is calculated before the new pool tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new pool balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (poolClaim * context.vaultState.totalVaultSharesGlobal) / context.vaultState.totalPoolClaim;
    }

    /// @notice Executes an exact in trade
    /// @param context strategy context
    /// @param params trade params
    /// @param sellToken address of the token to sell
    /// @param buyToken address of the token to buy
    /// @param amount token amount
    /// @param useDynamicSlippage true if the trade should be executed using dynamic slippage
    function _executeTradeExactIn(
        StrategyContext memory context,
        TradeParams memory params,
        address sellToken,
        address buyToken,
        uint256 amount,
        bool useDynamicSlippage
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        /// @dev this function can only handle exact in trades
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE || params.tradeType == TradeType.EXACT_IN_BATCH
        );
        /// @dev only certain vaults can use static slippage
        if (useDynamicSlippage) {
            require(params.oracleSlippagePercentOrLimit <= Constants.SLIPPAGE_LIMIT_PRECISION);
        } else {
            require(context.canUseStaticSlippage);
        }

        // Sell residual secondary balance
        Trade memory trade = Trade(
            params.tradeType,
            sellToken,
            buyToken,
            amount,
            useDynamicSlippage ? 0 : params.oracleSlippagePercentOrLimit,
            block.timestamp, // deadline
            params.exchangeData
        );

        // stETH generally has deeper liquidity than wstETH, setting tradeUnwrapped
        // to lets the contract trade in stETH instead of wstETH
        if (params.tradeUnwrapped) {
            if (sellToken == address(Deployments.WRAPPED_STETH)) {
                // Unwrap wstETH if tradeUnwrapped is true
                trade.sellToken = Deployments.WRAPPED_STETH.stETH();
                uint256 amountBeforeUnwrap = IERC20(trade.sellToken).balanceOf(address(this));
                // NOTE: the amount returned by unwrap is not always accurate for some reason
                Deployments.WRAPPED_STETH.unwrap(trade.amount);
                trade.amount = IERC20(trade.sellToken).balanceOf(address(this)) - amountBeforeUnwrap;
            }
            if (buyToken == address(Deployments.WRAPPED_STETH)) {
                // Unwrap wstETH if tradeUnwrapped is true
                trade.buyToken = Deployments.WRAPPED_STETH.stETH();
            }
        }

        if (useDynamicSlippage) {
            /// @dev params.oracleSlippagePercentOrLimit checked above
            (amountSold, amountBought) = trade._executeTradeWithDynamicSlippage(
                params.dexId, context.tradingModule, uint32(params.oracleSlippagePercentOrLimit)
            );
        } else {
            // Execute trade using static slippage
            (amountSold, amountBought) = trade._executeTrade(
                params.dexId, context.tradingModule
            );
        }

        if (params.tradeUnwrapped) {
            if (sellToken == address(Deployments.WRAPPED_STETH)) {
                // Setting amountSold to the original wstETH amount because _executeTradeWithDynamicSlippage
                // returns the amount of stETH sold in this case
                /// @notice amountSold == amount because this function only supports EXACT_IN trades
                amountSold = amount;
            }
            if (buyToken == address(Deployments.WRAPPED_STETH) && amountBought > 0) {
                // trade.buyToken == stETH here
                IERC20(trade.buyToken).checkApprove(address(Deployments.WRAPPED_STETH), amountBought);
                uint256 amountBeforeWrap = Deployments.WRAPPED_STETH.balanceOf(address(this));
                /// @notice the amount returned by wrap is not always accurate for some reason
                Deployments.WRAPPED_STETH.wrap(amountBought);
                amountBought = Deployments.WRAPPED_STETH.balanceOf(address(this)) - amountBeforeWrap;
            }
        }
    }

    /// @notice Helper function that determins the amount of vaultShares to mint for a given number
    /// of pool tokens
    /// @param strategyContext strategy context
    /// @param poolClaimMinted amount of pool tokens
    /// @return vaultSharesMinted amount of vault shares minted
    function _mintStrategyTokens(
        StrategyContext memory strategyContext,
        uint256 poolClaimMinted
    ) internal returns (uint256 vaultSharesMinted) {
        vaultSharesMinted = _convertPoolClaimToStrategyTokens(strategyContext, poolClaimMinted);

        // 0 vault shares here is usually due to rounding error 
        if (vaultSharesMinted == 0) {
            revert Errors.ZeroStrategyTokens();
        }

        // Update global accounting
        strategyContext.vaultState.totalPoolClaim += poolClaimMinted;
        strategyContext.vaultState.totalVaultSharesGlobal += vaultSharesMinted.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
    }

    /// @notice Helper function that determins the amount of pool claim to redeem for a given number
    /// of vault shares
    /// @param strategyContext strategy context
    /// @param vaultShares amount of vault shares
    /// @return poolClaim amount of pool tokens to redeem
    function _redeemStrategyTokens(
        StrategyContext memory strategyContext,
        uint256 vaultShares
    ) internal returns (uint256 poolClaim) {
        if (vaultShares == 0) {
            return poolClaim;
        }

        poolClaim = _convertStrategyTokensToPoolClaim(strategyContext, vaultShares);

        // 0 pool claim here is usually due to rounding error 
        if (poolClaim == 0) {
            revert Errors.ZeroPoolClaim();
        }

        // Update global accounting
        strategyContext.vaultState.totalPoolClaim -= poolClaim;
        strategyContext.vaultState.totalVaultSharesGlobal -= vaultShares.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
    }

    /// @notice Returns the pool claim threshold, which controls the max number of LP
    /// tokens the vault is allowed to hold
    /// @param totalPoolSupply total supply of the liquidity pool (after join)
    /// @param lpTokensMinted new lp tokens minted
    function _checkPoolThreshold(
        StrategyContext memory context,
        uint256 totalPoolSupply,
        uint256 lpTokensMinted
    ) internal pure {
        uint256 maxSupplyThreshold = (totalPoolSupply * context.vaultSettings.maxPoolShare) / VaultConstants.VAULT_PERCENT_BASIS;

        uint256 totalLPTokensAfterJoin = context.vaultState.totalPoolClaim + lpTokensMinted;
        if (maxSupplyThreshold < totalLPTokensAfterJoin)
            revert Errors.PoolShareTooHigh(totalLPTokensAfterJoin, maxSupplyThreshold);
    }
}
