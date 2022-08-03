// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StrategyContext, StrategyVaultState, SettlementState} from "../../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {SettlementUtils} from "../settlement/SettlementUtils.sol";
import {SecondaryBorrowUtils} from "../SecondaryBorrowUtils.sol";
import {Constants} from "../../../../global/Constants.sol";
import {VaultUtils} from "../VaultUtils.sol";

library StrategyUtils {
    using VaultUtils for StrategyVaultState;

    function _getTotalSupplyInMaturityAndSecondaryBorrowAmount(
        StrategyContext memory context,
        address account,
        uint256 maturity,
        uint256 strategyTokenAmount
    ) internal view returns (uint256 totalSupplyInMaturity, uint256 borrowedSecondaryfCashAmount) {
        if (account == address(this) || maturity - context.settlementPeriodInSeconds <= block.timestamp) {
            // In settlement
            SettlementState memory state = SettlementUtils._getSettlementState(maturity, strategyTokenAmount);
            totalSupplyInMaturity = state.totalStrategyTokensInMaturity;
        } else {
            totalSupplyInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
        }

        if (context.secondaryBorrowCurrencyId > 0) {
            if (account == address(this)) {
                // prettier-ignore
                (
                    /* uint256 debtShares */,
                    borrowedSecondaryfCashAmount
                ) = SecondaryBorrowUtils._getSettlementDebtSharesToRepay({
                    secondaryBorrowCurrencyId: context.secondaryBorrowCurrencyId,
                    strategyTokenAmount: strategyTokenAmount,
                    maturity: maturity, 
                    totalStrategyTokensInMaturity: totalSupplyInMaturity
                });
            } else {
                // prettier-ignore
                (
                    /* uint256 debtShares */,
                    borrowedSecondaryfCashAmount
                ) = SecondaryBorrowUtils._getAccountDebtSharesToRepay({
                    secondaryBorrowCurrencyId: context.secondaryBorrowCurrencyId, 
                    account: account,
                    maturity: maturity, 
                    strategyTokenAmount: strategyTokenAmount
                });
            }
        }
    }

    /// @notice Converts strategy tokens to BPT
    function _convertStrategyTokensToBPTClaim(
        StrategyContext memory context,
        uint256 strategyTokenAmount, 
        uint256 totalSupplyInMaturity
    ) internal pure returns (uint256 bptClaim) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18
            return (strategyTokenAmount * BalancerUtils.BALANCER_PRECISION) /
                uint256(Constants.INTERNAL_TOKEN_PRECISION);
        }

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);

        if (totalSupplyInMaturity == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18
            return (strategyTokenAmount * BalancerUtils.BALANCER_PRECISION) /
                uint256(Constants.INTERNAL_TOKEN_PRECISION);
        }

        bptClaim = (bptHeldInMaturity * strategyTokenAmount) / totalSupplyInMaturity;
    }

    /// @notice Converts BPT to strategy tokens
    function _convertBPTClaimToStrategyTokens(
        StrategyContext memory context,
        uint256 bptClaim, 
        uint256 totalSupplyInMaturity
    ) internal pure returns (uint256 strategyTokenAmount) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);

        if (bptHeldInMaturity == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (bptClaim * totalSupplyInMaturity) / bptHeldInMaturity;
    }
}
