// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import { StrategyContext, DynamicTradeParams } from "../../BalancerVaultTypes.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {TradeHandler} from "../../../../trading/TradeHandler.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {Constants} from "../../../../global/Constants.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {ITradingModule, Trade, TradeType} from "../../../../../interfaces/trading/ITradingModule.sol";

library StrategyUtils {
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
                BalancerConstants.BALANCER_PRECISION;
        }

        // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (bptClaim * context.vaultState.totalStrategyTokenGlobal) / context.totalBPTHeld;
    }

    function _executeDynamicTradeExactIn(
        DynamicTradeParams memory params,
        ITradingModule tradingModule,
        address sellToken,
        address buyToken,
        uint256 amount
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE || params.tradeType == TradeType.EXACT_IN_BATCH
        );

        // stETH generally has deeper liquidity than wstETH, setting tradeUnwrapped
        // to lets the contract trade in stETH instead of wstETH
        if (params.tradeUnwrapped && sellToken == address(Deployments.WRAPPED_STETH)) {
            sellToken = Deployments.WRAPPED_STETH.stETH();
            uint256 unwrappedAmount = IERC20(sellToken).balanceOf(address(this));
            // NOTE: the amount returned by unwrap is not always accurate for some reason
            Deployments.WRAPPED_STETH.unwrap(amount);
            amount = IERC20(sellToken).balanceOf(address(this)) - unwrappedAmount;
        }
        if (params.tradeUnwrapped && buyToken == address(Deployments.WRAPPED_STETH)) {
            buyToken = Deployments.WRAPPED_STETH.stETH();
        }

        // Sell residual secondary balance
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
            params.dexId, tradingModule, params.oracleSlippagePercent
        );

        if (
            params.tradeUnwrapped && 
            buyToken == address(Deployments.WRAPPED_STETH) && 
            amountBought > 0
        ) {
            IERC20(buyToken).checkApprove(address(Deployments.WRAPPED_STETH), amountBought);
            uint256 wrappedAmount = Deployments.WRAPPED_STETH.balanceOf(address(this));
            /// @notice the amount returned by wrap is not always accurate for some reason
            Deployments.WRAPPED_STETH.wrap(amountBought);
            amountBought = Deployments.WRAPPED_STETH.balanceOf(address(this)) - wrappedAmount;
        }
    }
}
