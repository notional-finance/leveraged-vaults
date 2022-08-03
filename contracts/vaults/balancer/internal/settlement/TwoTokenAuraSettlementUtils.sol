// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolContext, 
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyContext,
    OracleContext,
    TwoTokenAuraSettlementContext,
    NormalSettlementData, 
    RedeemParams, 
    SecondaryTradeParams,
    SettlementState,
    StrategyVaultSettings,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {SettlementUtils} from "./SettlementUtils.sol";
import {TwoTokenPoolUtils} from "../pool/TwoTokenPoolUtils.sol";
import {TwoTokenAuraStrategyUtils} from "../strategy/TwoTokenAuraStrategyUtils.sol";
import {SecondaryBorrowUtils} from "../SecondaryBorrowUtils.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library TwoTokenAuraSettlementUtils {
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using StrategyUtils for StrategyContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenAuraStrategyUtils for AuraStakingContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using VaultUtils for StrategyVaultState;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for SettlementState;
    
    /// @notice Redeems BPTs from the pool and checks if there is sufficient balance to settle on
    /// either one of the primary or secondary balances
    function _exitAndSettle(
        TwoTokenAuraSettlementContext memory context,
        NormalSettlementData memory data,
        uint256 bptToSettle,
        uint256 maturity,
        RedeemParams memory params
    ) private returns (bool completedSettlement, uint256 primaryBalance, uint256 secondaryBalance) {
        /// @notice minPrimary and minSecondary are validated before this function is called
        (primaryBalance, secondaryBalance) = context.stakingContext._unstakeAndExitPoolExactBPTIn({
            poolContext: context.poolContext,
            bptClaim: bptToSettle,
            minPrimary: params.minPrimary,
            minSecondary: params.minSecondary
        });

        primaryBalance += data.state.primarySettlementBalance;
        secondaryBalance += data.state.secondarySettlementBalance;

        // We can settle if we have enough to pay off either the primary side or the secondary size
        bool hasSufficientBalanceToSettle = (data.underlyingCashRequiredToSettle <= primaryBalance.toInt() ||
            data.borrowedSecondaryfCashAmountExternal <= secondaryBalance);

        if (hasSufficientBalanceToSettle) {
            // Settle secondary currency first
            if (data.borrowedSecondaryfCashAmountExternal > 0) {
                if (!data.state.inSettlement) {
                    Constants.NOTIONAL.initiateSecondaryBorrowSettlement(maturity);
                }

                // This method call will trade any primary balance into secondary to repay or it will
                // trade any excess secondary back into the primary currency
                primaryBalance = SecondaryBorrowUtils._repaySecondaryBorrow({
                    secondaryBorrowCurrencyId: context.strategyContext.secondaryBorrowCurrencyId,
                    account: address(this),
                    maturity: maturity,
                    debtSharesToRepay: data.debtSharesToRepay,
                    params: params,
                    secondaryBalance: secondaryBalance,
                    primaryBalance: primaryBalance
                });

                // Secondary balance should be 0 after repayment
                // Any residual balance should've been sold for primary currency
                secondaryBalance = 0;
            }

            // Settle primary currency with updated primaryBalance (from secondary currency trading)
            (completedSettlement, primaryBalance) = SettlementUtils._repayPrimaryDebt({
                underlyingCashRequiredToSettle: data.underlyingCashRequiredToSettle,
                maxUnderlyingSurplus: data.maxUnderlyingSurplus,
                redeemStrategyTokenAmount: data.redeemStrategyTokenAmount,
                maturity: maturity,
                primaryBalance: primaryBalance.toInt()
            });
        }
    }

    /// @notice Executes a normal vault settlement where BPT tokens are redeemed and returned tokens
    /// are traded accordingly
    /// @param maturity the maturity to settle
    /// @param strategyTokensToRedeem number of strategy tokens to redeem, 
    /// we do not authenticate this amount, only the slippage
    /// from minPrimary and minSecondary
    function _executeNormalSettlement(
        TwoTokenAuraSettlementContext memory context,
        SettlementState memory state,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) internal returns (bool completedSettlement) {
        require(strategyTokensToRedeem <= type(uint80).max); /// @dev strategyTokensToRedeem overflow
        
        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        context.poolContext._validateMinExitAmounts({
            oracleContext: context.oracleContext,
            tradingModule: context.strategyContext.tradingModule,
            minPrimary: params.minPrimary,
            minSecondary: params.minSecondary
        });

        uint256 bptToSettle = context.strategyContext._convertStrategyTokensToBPTClaim(
            strategyTokensToRedeem, state.totalStrategyTokensInMaturity
        );

        NormalSettlementData memory data = _normalSettlementData({
            strategyContext: context.strategyContext,
            poolContext: context.poolContext,
            state: state,
            maturity: maturity,
            redeemStrategyTokenAmount: strategyTokensToRedeem
        });

        // Update totalStrategyTokenGlobal in storage to keep it in sync
        // with _bptHeld() after we unstake and exit
        context.strategyContext.vaultState.totalStrategyTokenGlobal -= uint80(strategyTokensToRedeem);
        context.strategyContext.vaultState._setStrategyVaultState();

        // Exits BPT tokens from the pool and returns the most up to date balances
        uint256 primaryBalance;
        uint256 secondaryBalance;
        (
            completedSettlement,
            primaryBalance,
            secondaryBalance
        ) = _exitAndSettle(context, data, bptToSettle, maturity, params);

        // Mark the vault as settled
        if (maturity <= block.timestamp) {
            Constants.NOTIONAL.settleVault(address(this), maturity);
        }

        require(primaryBalance <= type(uint88).max); /// @dev primaryBalance overflow
        require(secondaryBalance <= type(uint88).max); /// @dev secondaryBalance overflow

        // Update settlement balances and strategy tokens redeemed
        SettlementState({
            primarySettlementBalance: uint88(primaryBalance), 
            secondarySettlementBalance: uint88(secondaryBalance), 
            totalStrategyTokensInMaturity: state.totalStrategyTokensInMaturity - uint80(strategyTokensToRedeem),
            inSettlement: true
        })._setSettlementState(maturity);

        emit SettlementUtils.VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem, completedSettlement); 
    }

    function _normalSettlementData(
        StrategyContext memory strategyContext,
        TwoTokenPoolContext memory poolContext,
        SettlementState memory state,
        uint256 maturity,
        uint256 redeemStrategyTokenAmount
    ) private view returns (NormalSettlementData memory) {
        // Get primary and secondary debt amounts from Notional
        // prettier-ignore
        (
            /* int256 assetCashRequiredToSettle */,
            int256 underlyingCashRequiredToSettle
        ) = Constants.NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        uint256 debtSharesToRepay;
        uint256 borrowedSecondaryfCashAmount;
        if (strategyContext.secondaryBorrowCurrencyId > 0) {
            (debtSharesToRepay, borrowedSecondaryfCashAmount) = SecondaryBorrowUtils._getDebtSharesToRepay(
                strategyContext.secondaryBorrowCurrencyId, address(this), maturity, redeemStrategyTokenAmount
            );
        }

        // If underlyingCashRequiredToSettle is 0 (no debt) or negative (surplus cash)
        // and borrowedSecondaryfCashAmount is also 0, no settlement is required
        if (
            underlyingCashRequiredToSettle <= 0 &&
            borrowedSecondaryfCashAmount == 0
        ) {
            revert Errors.SettlementNotRequired(); /// @dev no debt
        }

        // Convert fCash to secondary currency precision
        borrowedSecondaryfCashAmount =
            (borrowedSecondaryfCashAmount * (10**poolContext.secondaryDecimals)) /
            uint256(Constants.INTERNAL_TOKEN_PRECISION);

        return NormalSettlementData({
            secondaryBorrowCurrencyId: strategyContext.secondaryBorrowCurrencyId,
            maxUnderlyingSurplus: strategyContext.vaultSettings.maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            debtSharesToRepay: debtSharesToRepay,
            underlyingCashRequiredToSettle: underlyingCashRequiredToSettle,
            borrowedSecondaryfCashAmountExternal: borrowedSecondaryfCashAmount,
            state: state
        });
    }
}
