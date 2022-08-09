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

    function _getSecondaryBorrowAmount(
        StrategyContext memory context,
        address account,
        uint256 maturity,
        uint256 strategyTokenAmount
    ) internal view returns (uint256 borrowedSecondaryfCashAmount) {
        if (context.secondaryBorrowCurrencyId > 0) {
            if (account == address(this)) {
                uint256 totalSupplyInMaturity;
                
                if (maturity - context.settlementPeriodInSeconds <= block.timestamp) {
                    // In settlement
                    SettlementState memory state = SettlementUtils._getSettlementState(maturity, strategyTokenAmount);
                    totalSupplyInMaturity = state.totalStrategyTokensInMaturity;
                } else {
                    totalSupplyInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
                }

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
    function _convertStrategyTokensToBPTClaim(StrategyContext memory context, uint256 strategyTokenAmount)
        internal pure returns (uint256 bptClaim) {
        require(strategyTokenAmount <= context.vaultState.totalStrategyTokenGlobal);
        if (context.vaultState.totalStrategyTokenGlobal > 0) {            
            bptClaim = (strategyTokenAmount * context.totalBPTHeld) / context.vaultState.totalStrategyTokenGlobal;
        }
    }

    /// @notice Converts BPT to strategy tokens
    function _convertBPTClaimToStrategyTokens(StrategyContext memory context, uint256 bptClaim)
        internal pure returns (uint256 strategyTokenAmount) {
        if (context.totalBPTHeld == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (bptClaim * context.vaultState.totalStrategyTokenGlobal) / context.totalBPTHeld;
    }
}
