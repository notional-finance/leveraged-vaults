// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;

import {VaultHelper} from "./VaultHelper.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";

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
    error InSettlementCoolDown(uint32 lastTimestamp, uint32 coolDown);
    /// @notice settleVault called when there is no debt
    error SettlementNotRequired();

    event EmergencyVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeempStrategyTokenAmount
    );
    event NormalVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeempStrategyTokenAmount
    );

    struct NormalSettlementContext {
        uint256 maxUnderlyingSurplus;
        uint256 primarySettlementBalance;
        uint256 secondarySettlementBalance;
        uint256 redeemStrategyTokenAmount;
        int256 underlyingCashRequiredToSettle;
        uint256 debtSharesToRepay;
        uint256 borrowedSecondaryfCashAmount;
        uint32 settlementPeriodInSeconds;
        uint32 lastSettlementTimestamp;
        uint32 settlementCoolDownInMinutes;
        uint16 settlementSlippageLimit;
        uint16 secondaryBorrowCurrencyId;
        uint8 secondaryDecimals;
        VaultHelper.PoolContext poolContext;
    }

    struct EmergencySettlementContext {
        uint256 redeemStrategyTokenAmount;
        int256 expectedUnderlyingRedeemed;
        uint256 maxUnderlyingSurplus;
        uint256 bptTotalSupply;
        uint256 totalBPTHeld;
        uint32 settlementPeriodInSeconds;
        uint16 maxBalancerPoolShare;
    }

    function _validateSettlementSlippage(
        bytes memory data,
        uint32 slippageLimit
    ) private pure returns (VaultHelper.RedeemParams memory params) {
        params = abi.decode(data, (VaultHelper.RedeemParams));
        VaultHelper.RepaySecondaryCallbackParams memory callbackData = abi
            .decode(
                params.callbackData,
                (VaultHelper.RepaySecondaryCallbackParams)
            );
        if (callbackData.slippageLimit > slippageLimit) {
            revert SlippageTooHigh(callbackData.slippageLimit, slippageLimit);
        }
    }

    function _validateSettlementCoolDown(uint32 lastTimestamp, uint32 coolDown)
        private
        view
    {
        // Convert coolDown to seconds
        if (lastTimestamp + coolDown * 60 > block.timestamp)
            revert InSettlementCoolDown(lastTimestamp, coolDown);
    }

    function settleVaultPostMaturity(
        NormalSettlementContext memory context,
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    )
        external
        returns (
            bool settled,
            uint256 amountToRepay,
            uint256 primaryPostSettlement,
            uint256 secondaryPostSettlement
        )
    {
        if (block.timestamp < maturity) {
            revert HasNotMatured();
        }

        _validateSettlementCoolDown(
            context.lastSettlementTimestamp,
            context.settlementCoolDownInMinutes
        );

        VaultHelper.RedeemParams
            memory redeemParams = _validateSettlementSlippage(
                data,
                context.settlementSlippageLimit
            );

        return _normalSettlement(context, bptToSettle, maturity, redeemParams);
    }

    function settleVaultNormal(
        NormalSettlementContext memory context,
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    )
        external
        returns (
            bool settled,
            uint256 amountToRepay,
            uint256 primaryPostSettlement,
            uint256 secondaryPostSettlement
        )
    {
        if (maturity <= block.timestamp) {
            revert PostMaturitySettlement();
        }
        if (block.timestamp < maturity - context.settlementPeriodInSeconds) {
            revert NotInSettlementWindow();
        }

        // In settlement window
        _validateSettlementCoolDown(
            context.lastSettlementTimestamp,
            context.settlementCoolDownInMinutes
        );

        VaultHelper.RedeemParams
            memory redeemParams = _validateSettlementSlippage(
                data,
                context.settlementSlippageLimit
            );

        return _normalSettlement(context, bptToSettle, maturity, redeemParams);
    }

    function settleVaultEmergency(
        EmergencySettlementContext memory context,
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external {
        if (maturity <= block.timestamp) {
            revert PostMaturitySettlement();
        }
        // TODO: is this check necessary?
        if (maturity - context.settlementPeriodInSeconds <= block.timestamp) {
            revert InvalidEmergencySettlement();
        }

        // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
        uint256 emergencyBPTWithdrawThreshold = (context.bptTotalSupply *
            context.maxBalancerPoolShare) /
            VaultHelper.VAULT_PERCENTAGE_PRECISION;

        if (context.totalBPTHeld <= emergencyBPTWithdrawThreshold)
            revert InvalidEmergencySettlement();

        // desiredPoolShare = maxPoolShare * bufferPercentage
        uint256 desiredPoolShare = (context.maxBalancerPoolShare *
            VaultHelper.BALANCER_POOL_SHARE_BUFFER) /
            VaultHelper.VAULT_PERCENTAGE_PRECISION;
        uint256 desiredBPTAmount = (context.bptTotalSupply * desiredPoolShare) /
            VaultHelper.VAULT_PERCENTAGE_PRECISION;

        _emergencySettlement(
            context,
            context.totalBPTHeld - desiredBPTAmount,
            maturity,
            data
        );
    }

    function _normalSettlement(
        NormalSettlementContext memory context,
        uint256 bptToSettle,
        uint256 maturity,
        VaultHelper.RedeemParams memory redeemParams
    )
        private
        returns (
            bool settled,
            uint256 amountToRepay,
            uint256 primaryPostSettlement,
            uint256 secondaryPostSettlement
        )
    {
        // If underlyingCashRequiredToSettle is 0 (no debt) or negative (surplus cash)
        // and borrowedSecondaryfCashAmount is also 0, no settlement is required
        if (
            context.underlyingCashRequiredToSettle <= 0 &&
            context.borrowedSecondaryfCashAmount == 0
        ) {
            revert SettlementNotRequired(); /// @dev no debt
        }

        // Redeem BPT (doing this in another function to avoid stack issues)
        (uint256 primaryBalance, uint256 secondaryBalance) = VaultHelper
            ._exitPool(
                context.poolContext,
                bptToSettle,
                maturity,
                redeemParams.minPrimary,
                redeemParams.minSecondary
            );

        primaryBalance += context.primarySettlementBalance;
        secondaryBalance += context.secondarySettlementBalance;

        // Convert fCash to secondary currency precision
        context.borrowedSecondaryfCashAmount =
            (context.borrowedSecondaryfCashAmount *
                (10**context.secondaryDecimals)) /
            uint256(Constants.INTERNAL_TOKEN_PRECISION);

        // Let the token balances accumulate in this contract if we don't have
        // enough to pay off either side
        if (
            primaryBalance.toInt() < context.underlyingCashRequiredToSettle &&
            secondaryBalance < context.borrowedSecondaryfCashAmount
        ) {
            primaryPostSettlement = primaryBalance;
            secondaryPostSettlement = secondaryBalance;
        } else {
            // If we get to this point, we have enough to pay off either the primary
            // side or the secondary side

            // We repay the secondary debt first
            // (trading is handled in repaySecondaryCurrencyFromVault)
            if (context.debtSharesToRepay > 0) {
                // Primary balance is updated after secondary currency repayment
                primaryBalance = VaultHelper.repaySecondaryBorrow(
                    address(this),
                    context.secondaryBorrowCurrencyId,
                    maturity,
                    context.debtSharesToRepay,
                    redeemParams.secondarySlippageLimit,
                    redeemParams.callbackData,
                    primaryBalance,
                    secondaryBalance
                );
            }

            // Settle primary debt
            (
                settled,
                amountToRepay,
                primaryPostSettlement
            ) = _settlePrimaryCurrency(
                context,
                bptToSettle,
                primaryBalance.toInt(),
                maturity
            );

            // secondaryPostSettlement is 0 in this case
        }
    }

    function _settlePrimaryCurrency(
        NormalSettlementContext memory context,
        uint256 bptToSettle,
        int256 primaryAmount,
        uint256 maturity
    )
        private
        returns (
            bool settled,
            uint256 amountToRepay,
            uint256 primaryPostSettlement
        )
    {
        // Secondary debt is paid off, handle potential primary payoff
        // @audit there's a lot of flipping between uint and int here, maybe just convert primaryAmount to
        // int up front and then leave it that way?
        if (primaryAmount < context.underlyingCashRequiredToSettle) {
            // If primaryAmountAvailable < underlyingCashRequiredToSettle,
            // we need to redeem more BPT. So, we update primarySettlementBalance[maturity]
            // and wait for the next settlement call.
            primaryPostSettlement = primaryAmount.toUint();
        } else {
            // Calculate the amount of surplus cash after primary repayment
            // If underlyingCashRequiredToSettle < 0, that means there is excess
            // cash in the system. We add it to the surplus with the subtraction.
            int256 surplus = primaryAmount -
                context.underlyingCashRequiredToSettle;

            // Make sure we are not settling too much because we want
            // to preserve as much BPT as possible
            if (surplus > context.maxUnderlyingSurplus.toInt()) {
                revert RedeemingTooMuch(
                    primaryAmount,
                    context.underlyingCashRequiredToSettle
                );
            }

            if (maturity <= block.timestamp) {
                Constants.NOTIONAL.settleVault(address(this), maturity);
            }

            // Return the amount to repay back to the caller,
            // actual repayment happens in the calling contract
            amountToRepay = primaryAmount.toUint();
            settled = true;
        }
    }

    function _emergencySettlement(
        EmergencySettlementContext memory context,
        uint256 bptToSettle,
        uint256 maturity,
        bytes calldata data
    ) private {
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
        int256 surplus = context.expectedUnderlyingRedeemed -
            underlyingCashRequiredToSettle;

        // Make sure we not redeeming too much to underlying
        // This allows BPT to be accrued as the profit token.
        if (surplus > context.maxUnderlyingSurplus.toInt()) {
            revert RedeemingTooMuch(
                context.expectedUnderlyingRedeemed,
                underlyingCashRequiredToSettle
            );
        }

        // prettier-ignore
        (
            int256 assetCashPostRedemption,
            /* int256 underlyingCashPostRedemption */
        ) = Constants.NOTIONAL.redeemStrategyTokensToCash(maturity, context.redeemStrategyTokenAmount, data);

        emit EmergencyVaultSettlement(
            maturity,
            bptToSettle,
            context.redeemStrategyTokenAmount
        );
    }
}
