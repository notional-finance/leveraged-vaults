// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolContext, 
    NormalSettlementContext, 
    RedeemParams, 
    SecondaryTradeParams
} from "./BalancerVaultTypes.sol";
import {BalancerUtils} from "./internal/BalancerUtils.sol";
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
    error InSettlementCoolDown(uint32 lastSettlementTimestamp, uint32 coolDownInMinutes);
    /// @notice settleVault called when there is no debt
    error SettlementNotRequired();

    event EmergencyVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeemStrategyTokenAmount
    );

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

    function _repaySecondaryBorrow(
        address account,
        uint256 maturity,
        uint16 secondaryBorrowCurrencyId,
        uint256 debtSharesToRepay,
        RedeemParams memory params,
        uint256 secondaryBalance,
        uint256 primaryBalance
    ) internal returns (uint256 finalPrimaryBalance) {
        bytes memory returnData = Constants.NOTIONAL.repaySecondaryCurrencyFromVault(
            account,
            secondaryBorrowCurrencyId,
            maturity,
            debtSharesToRepay,
            params.minSecondaryLendRate,
            abi.encode(params.secondaryTradeParams, secondaryBalance)
        );

        // positive = primaryAmount increased (residual secondary => primary)
        // negative = primaryAmount decreased (primary => secondary shortfall)
        int256 netPrimaryBalance = abi.decode(returnData, (int256));

        // If primaryBalance + netPrimaryBalance < 0 it means that the repayment somehow over
        // sold the amount of primaryBalance that the user has redeemed, in that case we must
        // revert.
        finalPrimaryBalance = (primaryBalance.toInt() + netPrimaryBalance).toUint();
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
                primaryBalance = _repaySecondaryBorrow(
                    address(this),
                    maturity,
                    context.secondaryBorrowCurrencyId,
                    context.debtSharesToRepay,
                    params,
                    secondaryBalance,
                    primaryBalance
                );

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
}
