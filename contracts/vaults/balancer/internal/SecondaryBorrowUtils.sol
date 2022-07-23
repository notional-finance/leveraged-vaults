// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {DepositParams, RedeemParams, SecondaryTradeParams} from "../BalancerVaultTypes.sol";
import {SafeInt256} from "../../../global/SafeInt256.sol";
import {Constants} from "../../../global/Constants.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {TradeHandler} from "../../../trading/TradeHandler.sol";
import {ITradingModule, Trade, TradeType} from "../../../../interfaces/trading/ITradingModule.sol";

library SecondaryBorrowUtils {
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using TradeHandler for Trade;

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

    /// @notice Gets the amount of debt shares needed to pay off the secondary debt
    /// @param secondaryBorrowCurrencyId secondary borrow currency ID
    /// @param account account address
    /// @param maturity maturity timestamp
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return debtSharesToRepay amount of secondary debt shares
    /// @return borrowedSecondaryfCashAmount amount of secondary fCash borrowed
    function _getDebtSharesToRepay(
        uint16 secondaryBorrowCurrencyId, 
        address account, 
        uint256 maturity, 
        uint256 strategyTokenAmount
    ) internal view returns (uint256 debtSharesToRepay, uint256 borrowedSecondaryfCashAmount) {
        // prettier-ignore
        (uint256 totalfCashBorrowed, uint256 totalAccountDebtShares) = Constants.NOTIONAL.getSecondaryBorrow(
            address(this), secondaryBorrowCurrencyId, maturity
        );

        if (account == address(this)) {
            uint256 _totalSupply = NotionalUtils._totalSupplyInMaturity(maturity);

            if (_totalSupply == 0) return (0, 0);

            // If the vault is repaying the debt, then look across the total secondary
            // fCash borrowed
            debtSharesToRepay =
                (totalAccountDebtShares * strategyTokenAmount) / _totalSupply;
            borrowedSecondaryfCashAmount =
                (totalfCashBorrowed * strategyTokenAmount) / _totalSupply;
        } else {
            // prettier-ignore
            (
                /* uint256 debtSharesMaturity */,
                uint256[2] memory accountDebtShares,
                uint256 accountStrategyTokens
            ) = Constants.NOTIONAL.getVaultAccountDebtShares(account, address(this));

            debtSharesToRepay = accountStrategyTokens == 0 ? 0 :
                (accountDebtShares[0] * strategyTokenAmount) / accountStrategyTokens;
            borrowedSecondaryfCashAmount = totalAccountDebtShares == 0 ? 0 :
                (debtSharesToRepay * totalfCashBorrowed) / totalAccountDebtShares;
        }
    }

    function _repaySecondaryBorrow(
        uint16 secondaryBorrowCurrencyId,
        address account,
        uint256 maturity,
        uint256 strategyTokens,
        RedeemParams memory params,
        uint256 secondaryBalance,
        uint256 primaryBalance
    ) internal returns (uint256 finalPrimaryBalance) {
        // Returns the amount of secondary debt shares that need to be repaid
        (uint256 debtSharesToRepay, /*  */) = _getDebtSharesToRepay(
            secondaryBorrowCurrencyId, account, maturity, strategyTokens
        );

        if (debtSharesToRepay == 0) return primaryBalance;

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

    function _sellSecondaryBalance(
        SecondaryTradeParams memory params,
        ITradingModule tradingModule,
        address primaryToken,
        address secondaryToken,
        uint256 secondaryBalance
    ) internal returns (uint256 primaryPurchased) {
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE || params.tradeType == TradeType.EXACT_IN_BATCH
        );

        // Sell residual secondary balance
        Trade memory trade = Trade(
            params.tradeType,
            secondaryToken,
            primaryToken,
            secondaryBalance,
            0,
            block.timestamp, // deadline
            params.exchangeData
        );

        (/* */, primaryPurchased) = trade._executeTradeWithDynamicSlippage(
            params.dexId, tradingModule, params.oracleSlippagePercent
        );
    }

    function _handleSecondaryBorrowCallback(
        uint16 secondaryBorrowCurrencyId,
        ITradingModule tradingModule,
        address primaryToken,
        address secondaryToken,
        uint256 underlyingRequired,
        bytes calldata data
    ) internal returns (bytes memory returnData) {
        (
            bytes memory tradeParams,
            // secondaryBalance = secondary token amount from BPT redemption
            uint256 secondaryBalance
        ) = abi.decode(data, (bytes, uint256));

        SecondaryTradeParams memory params = abi.decode(tradeParams, (SecondaryTradeParams));

        int256 primaryBalanceBefore = TokenUtils.tokenBalance(primaryToken).toInt();

        if (secondaryBalance >= underlyingRequired) {
            // We already have enough to repay secondary debt
            // Update secondary balance before token transfer
            unchecked {
                secondaryBalance -= underlyingRequired;
            }
        } else {
            uint256 secondaryShortfall;
            // Not enough secondary balance to repay secondary debt,
            // sell some primary currency to cover the shortfall
            unchecked {
                secondaryShortfall = underlyingRequired - secondaryBalance;
            }

            require(
                params.tradeType == TradeType.EXACT_OUT_SINGLE || params.tradeType == TradeType.EXACT_OUT_BATCH
            );

            Trade memory trade = Trade(
                params.tradeType,
                primaryToken,
                secondaryToken,
                secondaryShortfall,
                0,
                block.timestamp, // deadline
                params.exchangeData
            );

            trade._executeTradeWithDynamicSlippage(params.dexId, tradingModule, params.oracleSlippagePercent);

            // @audit this should be validated by the returned parameters from the
            // trade execution
            // Setting secondaryBalance to 0 here because it should be
            // equal to underlyingRequired after the trade (validated by the TradingModule)
            // and 0 after the repayment token transfer.
            secondaryBalance = 0;
        }

        // Transfer required secondary balance to Notional
        if (secondaryBorrowCurrencyId == Constants.ETH_CURRENCY_ID) {
            payable(address(Constants.NOTIONAL)).transfer(underlyingRequired);
        } else {
            IERC20(secondaryToken).checkTransfer(address(Constants.NOTIONAL), underlyingRequired);
        }

        if (secondaryBalance > 0) {
            SecondaryBorrowUtils._sellSecondaryBalance(
                params, tradingModule, primaryToken, secondaryToken, secondaryBalance
            );
        }

        int256 primaryBalanceAfter = TokenUtils.tokenBalance(primaryToken).toInt();
        // Return primaryBalanceDiff
        // If primaryBalanceAfter > primaryBalanceBefore, residual secondary currency was
        // sold for primary currency
        // If primaryBalanceBefore > primaryBalanceAfter, primary currency was sold
        // for secondary currency to cover the shortfall
        return abi.encode(primaryBalanceAfter - primaryBalanceBefore);
    }
}
