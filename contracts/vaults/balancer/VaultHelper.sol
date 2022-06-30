// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    VaultContext, 
    PoolContext, 
    BoostContext,
    DepositParams,
    RedeemParams,
    SecondaryTradeParams
} from "./BalancerVaultTypes.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {BalancerVaultStorage} from "./BalancerVaultStorage.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";

abstract contract VaultHelper is BalancerVaultStorage {
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    error InvalidSecondaryBorrow(
        uint256 borrowedSecondaryAmount,
        uint256 optimalSecondaryAmount,
        uint256 secondaryfCashAmount
    );

    function _borrowSecondaryCurrency(
        address account,
        uint256 maturity,
        uint256 primaryAmount,
        DepositParams memory params
    ) internal returns (uint256 borrowedSecondaryAmount) {
        // If secondary currency is not specified then return
        if (SECONDARY_BORROW_CURRENCY_ID == 0) return 0;

        uint256 optimalSecondaryAmount = BalancerUtils.getOptimalSecondaryBorrowAmount(
            address(BALANCER_POOL_TOKEN),
            vaultSettings.oracleWindowInSeconds,
            PRIMARY_INDEX,
            PRIMARY_WEIGHT,
            SECONDARY_WEIGHT,
            PRIMARY_DECIMALS,
            SECONDARY_DECIMALS,
            primaryAmount
        );

        // Borrow secondary currency from Notional (tokens will be transferred to this contract)
        {
            uint256[2] memory fCashToBorrow;
            uint32[2] memory maxBorrowRate;
            uint32[2] memory minRollLendRate;
            fCashToBorrow[0] = params.secondaryfCashAmount;
            maxBorrowRate[0] = params.secondaryBorrowLimit;
            minRollLendRate[0] = params.secondaryRollLendLimit;
            uint256[2] memory tokensTransferred = NOTIONAL.borrowSecondaryCurrencyToVault(
                account,
                maturity,
                fCashToBorrow,
                maxBorrowRate,
                minRollLendRate
            );

            borrowedSecondaryAmount = tokensTransferred[0];
        }

        // Require the secondary borrow amount to be within some bounds of the optimal amount
        uint256 lowerLimit = (optimalSecondaryAmount * SECONDARY_BORROW_LOWER_LIMIT) / 100;
        uint256 upperLimit = (optimalSecondaryAmount * SECONDARY_BORROW_UPPER_LIMIT) / 100;
        if (borrowedSecondaryAmount < lowerLimit || upperLimit < borrowedSecondaryAmount) {
            revert InvalidSecondaryBorrow(
                borrowedSecondaryAmount,
                optimalSecondaryAmount,
                params.secondaryfCashAmount
            );
        }
    }

    function _joinPoolAndStake(
        uint256 primaryAmount,
        uint256 borrowedSecondaryAmount,
        uint256 minBPT
    ) internal returns (uint256 bptAmount) {
        uint256 balanceBefore = BALANCER_POOL_TOKEN.balanceOf(address(this));
        BalancerUtils.joinPoolExactTokensIn({
            poolId: BALANCER_POOL_ID,
            primaryAddress: address(_underlyingToken()),
            secondaryAddress: address(SECONDARY_TOKEN),
            primaryIndex: PRIMARY_INDEX,
            maxPrimaryAmount: primaryAmount,
            maxSecondaryAmount: borrowedSecondaryAmount,
            minBPT: minBPT
        });
        uint256 balanceAfter = BALANCER_POOL_TOKEN.balanceOf(address(this));

        bptAmount = balanceAfter - balanceBefore;

        // @audit need to check the maxBalancerPoolShare

        LIQUIDITY_GAUGE.deposit(bptAmount);
        // Transfer gauge token to VeBALDelegator
        BOOST_CONTROLLER.depositToken(address(LIQUIDITY_GAUGE), bptAmount);
    }

    function _unstakeAndExitPool(
        uint256 bptClaim,
        uint256 minPrimary,
        uint256 minSecondary
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        BOOST_CONTROLLER.withdrawToken(address(LIQUIDITY_GAUGE), bptClaim);
        LIQUIDITY_GAUGE.withdraw(bptClaim, false);

        address primaryToken = address(_underlyingToken());
        uint256 primaryBefore = TokenUtils.tokenBalance(primaryToken);
        uint256 secondaryBefore = TokenUtils.tokenBalance(address(SECONDARY_TOKEN));

        // If inside settlement:
        // @audit We need to validate that the spot price is within some band of the
        // oracle price before we exit here, we cannot trust that these minPrimary / minSecondary
        // values are correctly specified
        BalancerUtils.exitPoolExactBPTIn({
            poolId: BALANCER_POOL_ID,
            primaryAddress: primaryToken,
            secondaryAddress: address(SECONDARY_TOKEN),
            primaryIndex: PRIMARY_INDEX,
            minPrimaryAmount: minPrimary,
            minSecondaryAmount: minSecondary,
            bptExitAmount: bptClaim
        });

        primaryBalance = TokenUtils.tokenBalance(primaryToken) - primaryBefore;
        secondaryBalance = TokenUtils.tokenBalance(address(SECONDARY_TOKEN)) - secondaryBefore;
    }

    function repaySecondaryBorrow(
        address account,
        uint256 maturity,
        uint256 debtSharesToRepay,
        uint32 minSecondaryLendRate,
        bytes memory callbackData,
        uint256 secondaryBalance
    ) internal returns (int256 netPrimaryBalance) {
        bytes memory returnData = NOTIONAL.repaySecondaryCurrencyFromVault(
            account,
            SECONDARY_BORROW_CURRENCY_ID,
            maturity,
            debtSharesToRepay,
            minSecondaryLendRate,
            abi.encode(callbackData, secondaryBalance)
        );

        // positive = primaryAmount increased (residual secondary => primary)
        // negative = primaryAmount decreased (primary => secondary shortfall)
        netPrimaryBalance = abi.decode(returnData, (int256));
    }

    function _repaySecondaryBorrowCallback(
        address, /* secondaryToken */
        uint256 underlyingRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        require(SECONDARY_BORROW_CURRENCY_ID != 0); /// @dev invalid secondary currency

        (
            SecondaryTradeParams memory params,
            // secondaryBalance = secondary token amount from BPT redemption
            uint256 secondaryBalance
        ) = abi.decode(data, (SecondaryTradeParams, uint256));

        address primaryToken = address(_underlyingToken());
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

            Trade memory trade = Trade(
                TradeType.EXACT_OUT_SINGLE,
                primaryToken,
                address(SECONDARY_TOKEN),
                secondaryShortfall,
                // TradeHandler.getLimitAmount(
                //     address(TRADING_MODULE),
                //     uint16(TradeType.EXACT_OUT_SINGLE),
                //     primaryToken,
                //     address(SECONDARY_TOKEN),
                //     secondaryShortfall,
                //     params.oracleSlippagePercent
                // ),
                0,
                block.timestamp, // deadline
                params.exchangeData
            );

            _executeTrade(params.dexId, trade);

            // @audit this should be validated by the returned parameters from the
            // trade execution
            // Setting secondaryBalance to 0 here because it should be
            // equal to underlyingRequired after the trade (validated by the TradingModule)
            // and 0 after the repayment token transfer.
            secondaryBalance = 0;
        }

        // Transfer required secondary balance to Notional
        if (SECONDARY_BORROW_CURRENCY_ID == Constants.ETH_CURRENCY_ID) {
            payable(address(Constants.NOTIONAL)).transfer(underlyingRequired);
        } else {
            SECONDARY_TOKEN.checkTransfer(address(Constants.NOTIONAL), underlyingRequired);
        }

        if (secondaryBalance > 0) {
            sellSecondaryBalance(params, primaryToken, secondaryBalance);
        }

        int256 primaryBalanceAfter = TokenUtils.tokenBalance(primaryToken).toInt();
        // Return primaryBalanceDiff
        // If primaryBalanceAfter > primaryBalanceBefore, residual secondary currency was
        // sold for primary currency
        // If primaryBalanceBefore > primaryBalanceAfter, primary currency was sold
        // for secondary currency to cover the shortfall
        return abi.encode(primaryBalanceAfter - primaryBalanceBefore);
    }

    function sellSecondaryBalance(
        SecondaryTradeParams memory params,
        address primaryToken,
        uint256 secondaryBalance
    ) internal returns (uint256 primaryPurchased) {
        // Sell residual secondary balance
        Trade memory trade = Trade(
            TradeType.EXACT_IN_SINGLE,
            address(SECONDARY_TOKEN),
            primaryToken,
            secondaryBalance,
            // TradeHandler.getLimitAmount(
            //     address(TRADING_MODULE),
            //     uint16(TradeType.EXACT_IN_SINGLE),
            //     address(SECONDARY_TOKEN),
            //     primaryToken,
            //     secondaryBalance,
            //     params.oracleSlippagePercent
            // ),
            0,
            block.timestamp, // deadline
            params.exchangeData
        );

        (/* */, primaryPurchased) = _executeTrade(params.dexId, trade);
    }
}
