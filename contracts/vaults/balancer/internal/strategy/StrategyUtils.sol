// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    StrategyContext, 
    StrategyVaultState,
    SecondaryTradeParams
} from "../../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {TradeHandler} from "../../../../trading/TradeHandler.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {SettlementUtils} from "../settlement/SettlementUtils.sol";
import {Constants} from "../../../../global/Constants.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {ITradingModule, Trade, TradeType} from "../../../../../interfaces/trading/ITradingModule.sol";

library StrategyUtils {
    using VaultUtils for StrategyVaultState;
    using TradeHandler for Trade;
    using TokenUtils for IERC20;

    /// @notice Converts strategy tokens to BPT
    function _convertStrategyTokensToBPTClaim(StrategyContext memory context, uint256 strategyTokenAmount)
        internal pure returns (uint256 bptClaim) {
        require(strategyTokenAmount <= context.vaultState.totalStrategyTokenGlobal);
        if (context.vaultState.totalStrategyTokenGlobal > 0) {            
            bptClaim = (strategyTokenAmount * context.totalBPTHeld) / context.vaultState.totalStrategyTokenGlobal;
        }
    }

    /// @notice Converts BPT to strategy tokens
    function _convertBPTClaimToStrategyTokens(StrategyContext memory context, uint256 bptClaim)
        internal pure returns (uint256 strategyTokenAmount) {
        if (context.totalBPTHeld == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (bptClaim * context.vaultState.totalStrategyTokenGlobal) / context.totalBPTHeld;
    }

    function _sellSecondaryBalance(
        SecondaryTradeParams memory params,
        ITradingModule tradingModule,
        address primaryToken,
        address secondaryToken,
        uint256 secondaryBalance
    ) internal returns (uint256 primaryPurchased) {
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE || params.tradeType == TradeType.EXACT_IN_BATCH
        );

        // Unwrap wstETH if necessary to get better liquididty
        address sellToken = secondaryToken;
        if (params.tradeUnwrapped && secondaryToken == address(Constants.WRAPPED_STETH)) {
            sellToken = Constants.WRAPPED_STETH.stETH();
            uint256 unwrappedAmount = IERC20(sellToken).balanceOf(address(this));
            /// @notice the amount returned by unwrap is not always accurate for some reason
            Constants.WRAPPED_STETH.unwrap(secondaryBalance);
            secondaryBalance = IERC20(sellToken).balanceOf(address(this)) - unwrappedAmount;
        }

        // Sell residual secondary balance
        Trade memory trade = Trade(
            params.tradeType,
            sellToken,
            primaryToken,
            secondaryBalance,
            0,
            block.timestamp, // deadline
            params.exchangeData
        );

        (/* */, primaryPurchased) = trade._executeTradeWithDynamicSlippage(
            params.dexId, tradingModule, params.oracleSlippagePercent
        );
    }

    function _sellPrimaryBalance(
        SecondaryTradeParams memory params,
        ITradingModule tradingModule,
        address primaryToken,
        address secondaryToken,
        uint256 secondaryShortfall
    ) internal returns (uint256 secondaryPurchased) {
        require(
            params.tradeType == TradeType.EXACT_OUT_SINGLE || params.tradeType == TradeType.EXACT_OUT_BATCH
        );

        // Trade using stETH instead of wstETH if requested
        address buyToken = secondaryToken;
        if (params.tradeUnwrapped && secondaryToken == address(Constants.WRAPPED_STETH)) {
            buyToken = Constants.WRAPPED_STETH.stETH();
            secondaryShortfall = Constants.WRAPPED_STETH.getStETHByWstETH(secondaryShortfall);
        }

        Trade memory trade = Trade(
            params.tradeType,
            primaryToken,
            buyToken,
            secondaryShortfall,
            0,
            block.timestamp, // deadline
            params.exchangeData
        );

        (
            /* uint256 amountSold */, 
            secondaryPurchased
        ) = trade._executeTradeWithDynamicSlippage(params.dexId, tradingModule, params.oracleSlippagePercent);

        // Wrap stETH if necessary
        if (params.tradeUnwrapped && secondaryToken == address(Constants.WRAPPED_STETH)) {
            IERC20(buyToken).checkApprove(address(Constants.WRAPPED_STETH), secondaryPurchased);
            uint256 wrappedAmount = Constants.WRAPPED_STETH.balanceOf(address(this));
            /// @notice the amount returned by wrap is not always accurate for some reason
            Constants.WRAPPED_STETH.wrap(secondaryPurchased);
            secondaryPurchased = Constants.WRAPPED_STETH.balanceOf(address(this)) - wrappedAmount;
        }    
    }
}
