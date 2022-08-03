// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    SettlementState, 
    RedeemParams, 
    SecondaryTradeParams,
    StrategyContext,
    PoolContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";

library SettlementUtils {
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

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
    function _getSettlementState(uint256 maturity, uint256 strategyTokensToRedeem) 
        internal view returns (SettlementState memory) {
        SettlementState memory state = VaultUtils._getSettlementState(maturity);
        if (!state.isInitialized) {
            uint256 totalInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
            require(totalInMaturity <= type(uint80).max);
            state.totalStrategyTokensInMaturity = uint80(totalInMaturity);
        }
        // Make sure we have enough tokens in the current maturity to satisfy the
        // redemption request
        require(strategyTokensToRedeem <= state.totalStrategyTokensInMaturity);
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
            revert Errors.InSettlementCoolDown(lastSettlementTimestamp, coolDownInMinutes);

        params = abi.decode(data, (RedeemParams));
        SecondaryTradeParams memory callbackData = abi.decode(
            params.secondaryTradeParams, (SecondaryTradeParams)
        );

        if (callbackData.oracleSlippagePercent > slippageLimitPercent) {
            revert Errors.SlippageTooHigh(callbackData.oracleSlippagePercent, slippageLimitPercent);
        }
    }

    function _repayPrimaryDebt(
        int256 underlyingCashRequiredToSettle,
        uint256 maxUnderlyingSurplus,
        uint256 redeemStrategyTokenAmount,
        uint256 maturity,
        int256 primaryBalance
    ) internal returns (bool settled, uint256 primaryBalancePostSettlement) {
        // Check if we have enough to pay the primary debt off
        if (primaryBalance < underlyingCashRequiredToSettle) {
            // Not enough to repay, let the balance acumulate in this contract
            // settled = false
            primaryBalancePostSettlement = primaryBalance.toUint();
        } else {
            if (primaryBalance > 0) {
                // Calculate the amount of surplus cash after primary repayment
                // If underlyingCashRequiredToSettle < 0, that means there is excess
                // cash in the system. We add it to the surplus with the subtraction.
                int256 surplus = primaryBalance - underlyingCashRequiredToSettle;
    
                // Make sure we are not settling too much because we want
                // to preserve as much BPT as possible
                if (surplus > maxUnderlyingSurplus.toInt()) {
                    revert Errors.RedeemingTooMuch(
                        primaryBalance,
                        underlyingCashRequiredToSettle
                    );
                }

                // Call redeemStrategyTokensToCash with a special payload
                // to handle primary repayment
                Constants.NOTIONAL.redeemStrategyTokensToCash(
                    maturity, 
                    redeemStrategyTokenAmount,
                    abi.encode(primaryBalance.toUint())
                );
            }

            // primaryBalancePostSettlement = 0
            settled = true;
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

    function _getEmergencySettlementParams(
        StrategyContext memory strategyContext,
        PoolContext memory poolContext,
        uint256 maturity
    )  internal view returns(uint256 bptToSettle, uint256 maxUnderlyingSurplus) {
        StrategyVaultSettings memory settings = strategyContext.vaultSettings;
        StrategyVaultState memory state = strategyContext.vaultState;

        // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
        uint256 totalBPTSupply = IERC20(poolContext.pool).totalSupply();
        uint256 emergencyBPTWithdrawThreshold = settings._bptThreshold(totalBPTSupply);

        if (strategyContext.totalBPTHeld <= emergencyBPTWithdrawThreshold)
            revert Errors.InvalidEmergencySettlement();

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(
            NotionalUtils._totalSupplyInMaturity(maturity),
            strategyContext.totalBPTHeld
        );

        bptToSettle = _getEmergencySettlementBPTAmount({
            bptTotalSupply: totalBPTSupply,
            maxBalancerPoolShare: settings.maxBalancerPoolShare,
            totalBPTHeld: strategyContext.totalBPTHeld,
            bptHeldInMaturity: bptHeldInMaturity
        });
        maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
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
            revert Errors.RedeemingTooMuch(
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
