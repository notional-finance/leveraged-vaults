// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {DepositParams} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";

library SecondaryBorrowUtils {
    error InvalidSecondaryBorrow(
        uint256 borrowedSecondaryAmount,
        uint256 optimalSecondaryAmount,
        uint256 secondaryfCashAmount
    );

    function _borrowSecondaryCurrency(
        address account,
        uint256 maturity,
        uint256 optimalSecondaryAmount,
        DepositParams memory params
    ) internal returns (uint256 borrowedSecondaryAmount) {
        // Borrow secondary currency from Notional (tokens will be transferred to this contract)
        {
            uint256[2] memory fCashToBorrow;
            uint32[2] memory maxBorrowRate;
            uint32[2] memory minRollLendRate;
            fCashToBorrow[0] = params.secondaryfCashAmount;
            maxBorrowRate[0] = params.secondaryBorrowLimit;
            minRollLendRate[0] = params.secondaryRollLendLimit;
            uint256[2] memory tokensTransferred = Constants.NOTIONAL
                .borrowSecondaryCurrencyToVault(
                    account,
                    maturity,
                    fCashToBorrow,
                    maxBorrowRate,
                    minRollLendRate
                );

            borrowedSecondaryAmount = tokensTransferred[0];
        }

        // Require the secondary borrow amount to be within some bounds of the optimal amount
        uint256 lowerLimit = (optimalSecondaryAmount * Constants.SECONDARY_BORROW_LOWER_LIMIT) / 100;
        uint256 upperLimit = (optimalSecondaryAmount * Constants.SECONDARY_BORROW_UPPER_LIMIT) / 100;
        if (borrowedSecondaryAmount < lowerLimit || upperLimit < borrowedSecondaryAmount) {
            revert InvalidSecondaryBorrow(
                borrowedSecondaryAmount,
                optimalSecondaryAmount,
                params.secondaryfCashAmount
            );
        }
    } 
}