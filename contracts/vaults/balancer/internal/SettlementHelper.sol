// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolContext, 
    NormalSettlementContext, 
    RedeemParams, 
    SecondaryTradeParams
} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {Constants} from "../../../global/Constants.sol";
import {SafeInt256} from "../../../global/SafeInt256.sol";

library SettlementHelper {
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

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

    event EmergencyVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeemStrategyTokenAmount
    );

    /// @notice Validates the number of strategy tokens to redeem against
    /// the total strategy tokens already redeemed for the current maturity
    /// to ensure that we don't redeem tokens from other maturities
    function _validateTokensToRedeem(uint256 maturity, uint256 strategyTokensToRedeem) 
        internal view returns (SettlementState memory) {
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
    ) internal view returns (RedeemParams memory params) {
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

    function _repayPrimaryDebt(
        NormalSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        int256 primaryBalance
    ) private returns (bool settled, uint256 primaryBalancePostSettlement) {
        // Check if we have enough to pay the primary debt off
        if (primaryBalance < context.underlyingCashRequiredToSettle) {
            // Not enough to repay, let the balance acumulate in this contract
            // settled = false
            primaryBalancePostSettlement = primaryBalance.toUint();
        } else {
            if (primaryBalance > 0) {
                // Calculate the amount of surplus cash after primary repayment
                // If underlyingCashRequiredToSettle < 0, that means there is excess
                // cash in the system. We add it to the surplus with the subtraction.
                int256 surplus = primaryBalance - context.underlyingCashRequiredToSettle;
    
                // Make sure we are not settling too much because we want
                // to preserve as much BPT as possible
                if (surplus > context.maxUnderlyingSurplus.toInt()) {
                    revert RedeemingTooMuch(
                        primaryBalance,
                        context.underlyingCashRequiredToSettle
                    );
                }

                // Call redeemStrategyTokensToCash with a special payload
                // to handle primary repayment
                Constants.NOTIONAL.redeemStrategyTokensToCash(
                    maturity, 
                    strategyTokensToRedeem,
                    abi.encode(primaryBalance.toUint())
                );
            }

            // primaryBalancePostSettlement = 0
            settled = true;
        }
    }

    /// @notice Redeems BPTs from the pool and checks if there is sufficient balance to settle on
    /// either one of the primary or secondary balances
    function settleVaultNormal (
        NormalSettlementContext memory context,
        uint256 bptToSettle,
        uint256 maturity,
        RedeemParams memory params
    ) external returns (bool completedSettlement, uint256 primaryBalance, uint256 secondaryBalance) {
        /// @notice minPrimary and minSecondary are validated before this function is called
        // TODO: fix this
        /*(primaryBalance, secondaryBalance) = BalancerUtils._unstakeAndExitPoolExactBPTIn(
            context.poolContext,
            context.stakingContext,
            bptToSettle,
            params.minPrimary,
            params.minSecondary
        );*/

        primaryBalance += context.primarySettlementBalance;
        secondaryBalance += context.secondarySettlementBalance;

        // We can settle if we have enough to pay off either the primary side or the secondary size
        bool hasSufficientBalanceToSettle = (context.underlyingCashRequiredToSettle <= primaryBalance.toInt() ||
            context.borrowedSecondaryfCashAmountExternal <= secondaryBalance);

        if (hasSufficientBalanceToSettle) {
            // Settle secondary currency first
            if (context.borrowedSecondaryfCashAmountExternal > 0) {
                // This method call will trade any primary balance into secondary to repay or it will
                // trade any excess secondary back into the primary currency
                /*primaryBalance = _repaySecondaryBorrow(
                    address(this),
                    maturity,
                    context.secondaryBorrowCurrencyId,
                    context.debtSharesToRepay,
                    params,
                    secondaryBalance,
                    primaryBalance
                );*/

                // Secondary balance should be 0 after repayment
                // Any residual balance should've been sold for primary currency
                secondaryBalance = 0;
            }

            // Settle primary currency with updated primaryBalance (from secondary currency trading)
            (completedSettlement, primaryBalance) = _repayPrimaryDebt(
                context, maturity, context.redeemStrategyTokenAmount, primaryBalance.toInt());
        }
    }

    /// @notice Calculates the amount of BPT available for emergency settlement
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

    function settleVaultEmergency(
        uint256 maturity,
        uint256 bptToSettle,
        int256 expectedUnderlyingRedeemed,
        uint256 maxUnderlyingSurplus,
        uint256 redeemStrategyTokenAmount,
        bytes calldata data
    ) external {
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

    function _getEmergencySettlementParams(
        StrategyVaultSettings memory settings,
        StrategyVaultState memory state,
        uint256 maturity
    ) 
        private view returns(uint256 bptToSettle, uint256 maxUnderlyingSurplus) {
        // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
        uint256 totalBPTSupply = BALANCER_POOL_TOKEN.totalSupply();
        uint256 totalBPTHeld = _bptHeld();
        uint256 emergencyBPTWithdrawThreshold = settings._bptThreshold(totalBPTSupply);

        if (totalBPTHeld <= emergencyBPTWithdrawThreshold)
            revert SettlementHelper.InvalidEmergencySettlement();

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(
            NotionalUtils._totalSupplyInMaturity(maturity),
            totalBPTHeld
        );

        bptToSettle = SettlementHelper._getEmergencySettlementBPTAmount({
            bptTotalSupply: totalBPTSupply,
            maxBalancerPoolShare: settings.maxBalancerPoolShare,
            totalBPTHeld: totalBPTHeld,
            bptHeldInMaturity: bptHeldInMaturity
        });
        maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
    }

    event VaultSettlement(
        uint256 maturity,
        uint256 bptSettled,
        uint256 strategyTokensRedeemed,
        bool completedSettlement
    );

    /// @notice Executes a normal vault settlement where BPT tokens are redeemed and returned tokens
    /// are traded accordingly
    /// @param maturity the maturity to settle
    /// @param strategyTokensToRedeem number of strategy tokens to redeem, 
    /// we do not authenticate this amount, only the slippage
    /// from minPrimary and minSecondary
    function _executeNormalSettlement(
        SettlementState memory state,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) internal returns (bool completedSettlement) {
  /*      require(strategyTokensToRedeem <= type(uint80).max); /// @dev strategyTokensToRedeem overflow

        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        _validateMinExitAmounts(params.minPrimary, params.minSecondary);

        uint256 bptToSettle = _convertStrategyTokensToBPTClaim(strategyTokensToRedeem, maturity);
        NormalSettlementContext memory context = _normalSettlementContext(
            state, maturity, strategyTokensToRedeem);

        StrategyVaultState memory strategyVaultState = VaultUtils._getStrategyVaultState();
        strategyVaultState.totalStrategyTokenGlobal -= uint80(strategyTokensToRedeem);
        VaultUtils._setStrategyVaultState(strategyVaultState);

        // Exits BPT tokens from the pool and returns the most up to date balances
        uint256 primaryBalance;
        uint256 secondaryBalance;
        (
            completedSettlement,
            primaryBalance,
            secondaryBalance
        ) = SettlementHelper.settleVaultNormal(context, bptToSettle, maturity, params);

        // Mark the vault as settled
        if (maturity <= block.timestamp) {
            Constants.NOTIONAL.settleVault(address(this), maturity);
        }

        require(primaryBalance <= type(uint88).max); /// @dev primaryBalance overflow
        require(secondaryBalance <= type(uint88).max); /// @dev secondaryBalance overflow

        // Update settlement balances and strategy tokens redeemed
        VaultUtils._setSettlementState(maturity, SettlementState(
            uint88(primaryBalance), 
            uint88(secondaryBalance), 
            state.strategyTokensRedeemed + uint80(strategyTokensToRedeem)
        ));

        emit VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem, completedSettlement); */
    }

    function _normalSettlementContext(
        SettlementState memory state,
        uint256 maturity,
        uint256 redeemStrategyTokenAmount
    ) private view returns (NormalSettlementContext memory) {
        // Get primary and secondary debt amounts from Notional
        // prettier-ignore
        (
            /* int256 assetCashRequiredToSettle */,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        uint256 debtSharesToRepay;
        uint256 borrowedSecondaryfCashAmount;
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            (debtSharesToRepay, borrowedSecondaryfCashAmount) = SecondaryBorrowUtils._getDebtSharesToRepay(
                SECONDARY_BORROW_CURRENCY_ID, address(this), maturity, redeemStrategyTokenAmount
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
            (borrowedSecondaryfCashAmount * (10**SECONDARY_DECIMALS)) /
            uint256(Constants.INTERNAL_TOKEN_PRECISION);

        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
        return
            NormalSettlementContext({
                secondaryBorrowCurrencyId: SECONDARY_BORROW_CURRENCY_ID,
                maxUnderlyingSurplus: strategyVaultSettings.maxUnderlyingSurplus,
                primarySettlementBalance: state.primarySettlementBalance,
                secondarySettlementBalance: state.secondarySettlementBalance,
                redeemStrategyTokenAmount: redeemStrategyTokenAmount,
                debtSharesToRepay: debtSharesToRepay,
                underlyingCashRequiredToSettle: underlyingCashRequiredToSettle,
                borrowedSecondaryfCashAmountExternal: borrowedSecondaryfCashAmount,
                poolContext: _twoTokenPoolContext(),
                stakingContext: _auraStakingContext()
            });
    }
}
