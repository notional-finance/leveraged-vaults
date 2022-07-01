// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolContext, 
    NormalSettlementContext, 
    RedeemParams, 
    SecondaryTradeParams
} from "./BalancerVaultTypes.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
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
    event PostMaturityVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeempStrategyTokenAmount
    );
    event NormalVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeempStrategyTokenAmount
    );

    function _decodeParamsAndValidate(uint32 lastTimestamp, uint32 coolDown, uint32 slippageLimit, bytes memory data)
        internal
        view returns (RedeemParams memory params)
    {
        // Convert coolDown to seconds
        if (lastTimestamp + coolDown * 60 > block.timestamp)
            revert InSettlementCoolDown(lastTimestamp, coolDown);

        params = abi.decode(data, (RedeemParams));
        SecondaryTradeParams memory callbackData = abi.decode(
            params.secondaryTradeParams, (SecondaryTradeParams)
        );

        if (callbackData.oracleSlippagePercent > slippageLimit) {
            revert SlippageTooHigh(callbackData.oracleSlippagePercent, slippageLimit);
        }
    }

    function _settleVaultNormal (
        NormalSettlementContext memory context,
        uint256 bptToSettle,
        RedeemParams memory params
    ) internal returns (bool canSettle, uint256 primaryBalance, uint256 secondaryBalance) {
        // Redeem BPT (doing this in another function to avoid stack issues)

        /// @notice minPrimary and minSecondary are validated before this function is called
        (primaryBalance, secondaryBalance) = BalancerUtils._unstakeAndExitPoolExactBPTIn(
            context.poolContext,
            context.boostContext,
            bptToSettle,
            params.minPrimary,
            params.minSecondary
        );

        primaryBalance += context.primarySettlementBalance;
        secondaryBalance += context.secondarySettlementBalance;

        // We can settle if we have enough to pay off either the primary side or the secondary size
        canSettle = (context.underlyingCashRequiredToSettle <= primaryBalance.toInt() ||
            context.borrowedSecondaryfCashAmountExternal <= secondaryBalance);
    }

    function _settlePrimaryCurrency (
        int256 underlyingCashRequiredToSettle,
        uint256 maxUnderlyingSurplus,
        int256 primaryAmount,
        uint256 maturity
    )
        internal
        returns (
            bool settled,
            uint256 primaryAmountToRepay
        )
    {
        // Secondary debt is paid off, handle potential primary payoff
        if (primaryAmount >= underlyingCashRequiredToSettle) {
            // Calculate the amount of surplus cash after primary repayment
            // If underlyingCashRequiredToSettle < 0, that means there is excess
            // cash in the system. We add it to the surplus with the subtraction.
            int256 surplus = primaryAmount - underlyingCashRequiredToSettle;
 
            // Make sure we are not settling too much because we want
            // to preserve as much BPT as possible
            if (surplus > maxUnderlyingSurplus.toInt()) {
                revert RedeemingTooMuch(
                    primaryAmount,
                    underlyingCashRequiredToSettle
                );
            }

            if (maturity <= block.timestamp) {
                Constants.NOTIONAL.settleVault(address(this), maturity);
            }

            // Return the amount to repay back to the caller,
            // actual repayment happens in the calling contract
            primaryAmountToRepay = primaryAmount.toUint();
            settled = true;
        }
    }

    /// @notice Calculates the amount of BPT available for emergency settlement
    function _getEmergencySettlementBPTAmount(
        uint256 bptTotalSupply,
        uint16 maxBalancerPoolShare,
        uint256 totalBPTHeld,
        uint256 bptHeldInMaturity
    ) internal returns (uint256 bptToSettle) {
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
        (
            int256 assetCashPostRedemption,
            /* int256 underlyingCashPostRedemption */
        ) = Constants.NOTIONAL.redeemStrategyTokensToCash(maturity, redeemStrategyTokenAmount, data);

        emit EmergencyVaultSettlement(
            maturity,
            bptToSettle,
            redeemStrategyTokenAmount
        );
    }
}
