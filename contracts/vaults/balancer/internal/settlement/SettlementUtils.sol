// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    RedeemParams, 
    DynamicTradeParams,
    StrategyContext,
    PoolContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";

library SettlementUtils {
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using StrategyUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

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
        DynamicTradeParams memory callbackData = abi.decode(
            params.secondaryTradeParams, (DynamicTradeParams)
        );

        if (callbackData.oracleSlippagePercent > slippageLimitPercent) {
            revert Errors.SlippageTooHigh(callbackData.oracleSlippagePercent, slippageLimitPercent);
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

    function _executeSettlement(
        StrategyContext memory context,
        uint256 maturity,
        int256 expectedUnderlyingRedeemed,
        uint256 redeemStrategyTokenAmount,
        RedeemParams memory params
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
        if (surplus > context.vaultSettings.maxUnderlyingSurplus.toInt()) {
            revert Errors.RedeemingTooMuch(
                expectedUnderlyingRedeemed,
                underlyingCashRequiredToSettle
            );
        }

        Constants.NOTIONAL.redeemStrategyTokensToCash(
            maturity, redeemStrategyTokenAmount, abi.encode(params)
        );
    }
}
