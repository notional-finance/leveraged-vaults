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
} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {Constants} from "../../../global/Constants.sol";
import {SafeInt256} from "../../../global/SafeInt256.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {VaultUtils} from "./VaultUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {TwoTokenAuraStrategyUtils} from "./TwoTokenAuraStrategyUtils.sol";
import {SecondaryBorrowUtils} from "./SecondaryBorrowUtils.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";

library SettlementHelper {
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenAuraStrategyUtils for AuraStakingContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using VaultUtils for StrategyVaultState;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for SettlementState;

    error NotInSettlementWindow();
    error InvalidEmergencySettlement();
    error HasNotMatured();
    error PostMaturitySettlement();
    error RedeemingTooMuch(
        int256 underlyingRedeemed,
        int256 underlyingCashRequiredToSettle
    );
    error SlippageTooHigh(uint32 slippage, uint32 limit);
    error InSettlementCoolDown(uint32 lastSettlementTimestamp, uint32 coolDownInMinutes);
    /// @notice settleVault called when there is no debt
    error SettlementNotRequired();

    event VaultSettlement(
        uint256 maturity,
        uint256 bptSettled,
        uint256 strategyTokensRedeemed,
        bool completedSettlement
    );

    event EmergencyVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeemStrategyTokenAmount
    );

    /// @notice Validates the number of strategy tokens to redeem against
    /// the total strategy tokens already redeemed for the current maturity
    /// to ensure that we don't redeem tokens from other maturities
    function _validateTokensToRedeem(uint256 maturity, uint256 strategyTokensToRedeem) 
        private view returns (SettlementState memory) {
        SettlementState memory state = VaultUtils._getSettlementState(maturity);
        uint256 totalInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
        require(state.strategyTokensRedeemed + strategyTokensToRedeem <= totalInMaturity);
        return state;
    }

    /// @notice Validates settlement parameters, including that the settlement is
    /// past a specified cool down period and that the slippage passed in by the caller
    /// does not exceed the designated threshold.
    /// @param lastSettlementTimestamp the last time the vault was settled
    /// @param coolDownInMinutes configured length of time required between settlements to ensure that
    /// slippage thresholds are respected (gives the market time to arbitrage back into position)
    /// @param slippageLimitPercent configured limit on the slippage from the oracle price allowed
    /// @param data trade parameters passed into settlement
    /// @return params abi decoded redemption parameters
    function _decodeParamsAndValidate(
        uint32 lastSettlementTimestamp,
        uint32 coolDownInMinutes,
        uint32 slippageLimitPercent,
        bytes memory data
    ) private view returns (RedeemParams memory params) {
        // Convert coolDown to seconds
        if (lastSettlementTimestamp + (coolDownInMinutes * 60) > block.timestamp)
            revert InSettlementCoolDown(lastSettlementTimestamp, coolDownInMinutes);

        params = abi.decode(data, (RedeemParams));
        SecondaryTradeParams memory callbackData = abi.decode(
            params.secondaryTradeParams, (SecondaryTradeParams)
        );

        if (callbackData.oracleSlippagePercent > slippageLimitPercent) {
            revert SlippageTooHigh(callbackData.oracleSlippagePercent, slippageLimitPercent);
        }

    }

    function _settleVaultNormal(
        TwoTokenAuraSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) internal {        
        SettlementState memory state = _validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = _decodeParamsAndValidate(
            context.strategyContext.vaultState.lastSettlementTimestamp,
            context.strategyContext.vaultSettings.settlementCoolDownInMinutes,
            context.strategyContext.vaultSettings.settlementSlippageLimitPercent,
            data
        );

        _executeNormalSettlement({
            context: context,
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            params: params
        });

        context.strategyContext.vaultState.lastSettlementTimestamp = uint32(block.timestamp);
        context.strategyContext.vaultState._setStrategyVaultState();
    }

    function _settleVaultPostMaturity(
        TwoTokenAuraSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) internal {
        SettlementState memory state = _validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = _decodeParamsAndValidate(
            context.strategyContext.vaultState.lastPostMaturitySettlementTimestamp,
            context.strategyContext.vaultSettings.postMaturitySettlementCoolDownInMinutes,
            context.strategyContext.vaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );

        _executeNormalSettlement({
            context: context,
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            params: params
        });

        context.strategyContext.vaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
        context.strategyContext.vaultState._setStrategyVaultState();  
    }
    
    function _getEmergencySettlementParams(
        StrategyContext memory strategyContext,
        PoolContext memory poolContext,
        uint256 maturity
    )  private view returns(uint256 bptToSettle, uint256 maxUnderlyingSurplus) {
        StrategyVaultSettings memory settings = strategyContext.vaultSettings;
        StrategyVaultState memory state = strategyContext.vaultState;

        // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
        uint256 totalBPTSupply = IERC20(poolContext.pool).totalSupply();
        uint256 emergencyBPTWithdrawThreshold = settings._bptThreshold(totalBPTSupply);

        if (strategyContext.totalBPTHeld <= emergencyBPTWithdrawThreshold)
            revert SettlementHelper.InvalidEmergencySettlement();

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(
            NotionalUtils._totalSupplyInMaturity(maturity),
            strategyContext.totalBPTHeld
        );

        bptToSettle = SettlementHelper._getEmergencySettlementBPTAmount({
            bptTotalSupply: totalBPTSupply,
            maxBalancerPoolShare: settings.maxBalancerPoolShare,
            totalBPTHeld: strategyContext.totalBPTHeld,
            bptHeldInMaturity: bptHeldInMaturity
        });
        maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
    }

    function _settleVaultEmergency(
        TwoTokenAuraSettlementContext memory context,
        uint256 maturity,
        bytes calldata data
    ) internal {
        (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = _getEmergencySettlementParams(
            context.strategyContext, context.poolContext.basePool, maturity
        );

        uint256 redeemStrategyTokenAmount = context.strategyContext._convertBPTClaimToStrategyTokens(
            bptToSettle, maturity
        );

        int256 expectedUnderlyingRedeemed = context.strategyContext._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            account: address(this),
            strategyTokenAmount: redeemStrategyTokenAmount,
            maturity: maturity
        });

        _executeEmergencySettlement({
            maturity: maturity,
            bptToSettle: bptToSettle,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            maxUnderlyingSurplus: maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            data: data
        });       
    }

    function _repayPrimaryDebt(
        NormalSettlementData memory data,
        uint256 maturity,
        int256 primaryBalance
    ) private returns (bool settled, uint256 primaryBalancePostSettlement) {
        // Check if we have enough to pay the primary debt off
        if (primaryBalance < data.underlyingCashRequiredToSettle) {
            // Not enough to repay, let the balance acumulate in this contract
            // settled = false
            primaryBalancePostSettlement = primaryBalance.toUint();
        } else {
            if (primaryBalance > 0) {
                // Calculate the amount of surplus cash after primary repayment
                // If underlyingCashRequiredToSettle < 0, that means there is excess
                // cash in the system. We add it to the surplus with the subtraction.
                int256 surplus = primaryBalance - data.underlyingCashRequiredToSettle;
    
                // Make sure we are not settling too much because we want
                // to preserve as much BPT as possible
                if (surplus > data.maxUnderlyingSurplus.toInt()) {
                    revert RedeemingTooMuch(
                        primaryBalance,
                        data.underlyingCashRequiredToSettle
                    );
                }

                // Call redeemStrategyTokensToCash with a special payload
                // to handle primary repayment
                Constants.NOTIONAL.redeemStrategyTokensToCash(
                    maturity, 
                    data.redeemStrategyTokenAmount,
                    abi.encode(primaryBalance.toUint())
                );
            }

            // primaryBalancePostSettlement = 0
            settled = true;
        }
    }

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

        primaryBalance += data.primarySettlementBalance;
        secondaryBalance += data.secondarySettlementBalance;

        // We can settle if we have enough to pay off either the primary side or the secondary size
        bool hasSufficientBalanceToSettle = (data.underlyingCashRequiredToSettle <= primaryBalance.toInt() ||
            data.borrowedSecondaryfCashAmountExternal <= secondaryBalance);

        if (hasSufficientBalanceToSettle) {
            // Settle secondary currency first
            if (data.borrowedSecondaryfCashAmountExternal > 0) {
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
            (completedSettlement, primaryBalance) = _repayPrimaryDebt(
                data, maturity, primaryBalance.toInt()
            );
        }
    }

    /// @notice Calculates the amount of BPT availTable for emergency settlement
    function _getEmergencySettlementBPTAmount(
        uint256 bptTotalSupply,
        uint16 maxBalancerPoolShare,
        uint256 totalBPTHeld,
        uint256 bptHeldInMaturity
    ) internal pure returns (uint256 bptToSettle) {
        // desiredPoolShare = maxPoolShare * bufferPercentage
        uint256 desiredPoolShare = (maxBalancerPoolShare *
            Constants.BALANCER_POOL_SHARE_BUFFER) /
            Constants.VAULT_PERCENT_BASIS;
        uint256 desiredBPTAmount = (bptTotalSupply * desiredPoolShare) /
            Constants.VAULT_PERCENT_BASIS;
        
        bptToSettle = totalBPTHeld - desiredBPTAmount;

        // Check to make sure we are not settling more than the amount of BPT
        // available in the current maturity
        // If more settlement is needed, call settleVaultEmergency
        // again with a different maturity
        if (bptToSettle > bptHeldInMaturity) {
            bptToSettle = bptHeldInMaturity;
        }
    }

    function _executeEmergencySettlement(
        uint256 maturity,
        uint256 bptToSettle,
        int256 expectedUnderlyingRedeemed,
        uint256 maxUnderlyingSurplus,
        uint256 redeemStrategyTokenAmount,
        bytes calldata data
    ) internal {
        // prettier-ignore
        (
            /* int256 assetCashRequiredToSettle */,
            int256 underlyingCashRequiredToSettle
        ) = Constants.NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        // A negative surplus here means the account is insolvent
        // (either expectedUnderlyingRedeemed is negative or
        // expectedUnderlyingRedeemed is less than underlyingCashRequiredToSettle).
        // If that's the case, we should just redeem and repay as much as possible (surplus
        // check is ignored because maxUnderlyingSurplus can never be negative).
        // If underlyingCashRequiredToSettle is negative, that means we already have surplus cash
        // on the Notional side, it will just make the surplus larger and potentially
        // cause it to go over maxUnderlyingSurplus.
        int256 surplus = expectedUnderlyingRedeemed -
            underlyingCashRequiredToSettle;

        // Make sure we not redeeming too much to underlying
        // This allows BPT to be accrued as the profit token.
        if (surplus > maxUnderlyingSurplus.toInt()) {
            revert RedeemingTooMuch(
                expectedUnderlyingRedeemed,
                underlyingCashRequiredToSettle
            );
        }

        // prettier-ignore
        Constants.NOTIONAL.redeemStrategyTokensToCash(maturity, redeemStrategyTokenAmount, data);

        emit EmergencyVaultSettlement(
            maturity,
            bptToSettle,
            redeemStrategyTokenAmount
        );
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
            strategyTokensToRedeem, maturity
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
        SettlementState(
            uint88(primaryBalance), 
            uint88(secondaryBalance), 
            state.strategyTokensRedeemed + uint80(strategyTokensToRedeem)
        )._setSettlementState(maturity);

        emit VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem, completedSettlement); 
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
            revert SettlementHelper.SettlementNotRequired(); /// @dev no debt
        }

        // Convert fCash to secondary currency precision
        borrowedSecondaryfCashAmount =
            (borrowedSecondaryfCashAmount * (10**poolContext.secondaryDecimals)) /
            uint256(Constants.INTERNAL_TOKEN_PRECISION);

        return
            NormalSettlementData({
                secondaryBorrowCurrencyId: strategyContext.secondaryBorrowCurrencyId,
                maxUnderlyingSurplus: strategyContext.vaultSettings.maxUnderlyingSurplus,
                primarySettlementBalance: state.primarySettlementBalance,
                secondarySettlementBalance: state.secondarySettlementBalance,
                redeemStrategyTokenAmount: redeemStrategyTokenAmount,
                debtSharesToRepay: debtSharesToRepay,
                underlyingCashRequiredToSettle: underlyingCashRequiredToSettle,
                borrowedSecondaryfCashAmountExternal: borrowedSecondaryfCashAmount
            });
    }
}
