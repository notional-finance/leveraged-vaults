// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {TradeParams, StrategyContext, RedeemParams} from "../../VaultTypes.sol";
import {VaultState} from "../../../../global/Types.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {Constants} from "../../../../global/Constants.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {VaultConstants} from "../../VaultConstants.sol";
import {StrategyUtils} from "../../internal/strategy/StrategyUtils.sol";
import {VaultStorage, StrategyVaultSettings, StrategyVaultState} from "../../VaultStorage.sol";

library SettlementUtils {
    using TypeConvert for uint256;
    using TypeConvert for int256;
    using StrategyUtils for StrategyContext;
    using VaultStorage for StrategyVaultSettings;

    /// @notice Validates that the slippage passed in by the caller
    /// does not exceed the designated threshold.
    /// @param slippageLimitPercent configured limit on the slippage from the oracle price allowed
    /// @param data trade parameters passed into settlement
    /// @return params abi decoded redemption parameters
    function _decodeParamsAndValidate(
        uint32 slippageLimitPercent,
        bytes memory data
    ) internal view returns (RedeemParams memory params) {
        params = abi.decode(data, (RedeemParams));
        if (params.secondaryTradeParams.length != 0) {
            TradeParams memory callbackData = abi.decode(
                params.secondaryTradeParams, (TradeParams)
            );

            if (slippageLimitPercent < callbackData.oracleSlippagePercentOrLimit) {
                revert Errors.SlippageTooHigh(callbackData.oracleSlippagePercentOrLimit, slippageLimitPercent);
            }
        }
    }

    /// @notice Validates that the settlement is past a specified cool down period.
    /// @param lastSettlementTimestamp the last time the vault was settled
    /// @param coolDownInMinutes configured length of time required between settlements to ensure that
    /// slippage thresholds are respected (gives the market time to arbitrage back into position)
    function _validateCoolDown(uint32 lastSettlementTimestamp, uint32 coolDownInMinutes) internal view {
        // Convert coolDown to seconds
        if (lastSettlementTimestamp + (coolDownInMinutes * 60) > block.timestamp)
            revert Errors.InSettlementCoolDown(lastSettlementTimestamp, coolDownInMinutes);
    }

    /// @notice Calculates the amount of pool claim available for emergency settlement
    function _getEmergencySettlementPoolClaimAmount(
        uint256 totalPoolSupply,
        uint16 maxPoolShare,
        uint256 totalPoolClaim,
        uint256 poolClaimInMaturity
    ) private pure returns (uint256 poolClaimToSettle) {
        // desiredPoolShare = maxPoolShare * bufferPercentage
        uint256 desiredPoolShare = (maxPoolShare *
            VaultConstants.POOL_SHARE_BUFFER) /
            VaultConstants.VAULT_PERCENT_BASIS;
        uint256 desiredPoolClaimAmount = (totalPoolSupply * desiredPoolShare) /
            VaultConstants.VAULT_PERCENT_BASIS;
        
        poolClaimToSettle = totalPoolClaim - desiredPoolClaimAmount;

        // Check to make sure we are not settling more than the amount of pool claim
        // available in the current maturity
        // If more settlement is needed, call settleVaultEmergency
        // again with a different maturity
        if (poolClaimToSettle > poolClaimInMaturity) {
            poolClaimToSettle = poolClaimInMaturity;
        }
    }

    function _totalSupplyInMaturity(uint256 maturity) private view returns (uint256) {
        VaultState memory vaultState = Deployments.NOTIONAL.getVaultState(address(this), maturity);
        return vaultState.totalVaultShares;
    }
    
    function _getPoolClaimHeldInMaturity(
        StrategyVaultState memory strategyVaultState, 
        uint256 totalSupplyInMaturity,
        uint256 totalPoolClaimHeld
    ) private pure returns (uint256 poolClaimHeldInMaturity) {
        if (strategyVaultState.totalVaultSharesGlobal == 0) return 0;
        poolClaimHeldInMaturity =
            (totalPoolClaimHeld * totalSupplyInMaturity) /
            strategyVaultState.totalVaultSharesGlobal;
    }

}