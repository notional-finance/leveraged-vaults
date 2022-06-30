// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    VaultContext, 
    PoolContext, 
    BoostContext, 
    DepositParams, 
    RedeemParams, 
    RepaySecondaryCallbackParams
} from "./BalancerVaultTypes.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {BalancerVaultStorage} from "./BalancerVaultStorage.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";

abstract contract VaultHelper is BalancerVaultStorage {
    using TradeHandler for Trade;
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    error InvalidSecondaryBorrow(
        uint256 borrowedSecondaryAmount,
        uint256 optimalSecondaryAmount,
        uint256 secondaryfCashAmount
    );
    error BalancerPoolShareTooHigh(uint256 totalBPTHeld, uint256 bptThreshold);

    function _borrowSecondaryCurrency(
        address account,
        uint256 maturity,
        uint256 primaryAmount,
        DepositParams memory params
    ) internal returns (uint256 borrowedSecondaryAmount) {
        // If secondary currency is not specified then return
        if (SECONDARY_BORROW_CURRENCY_ID == 0) return 0;

        uint256 optimalSecondaryAmount = BalancerUtils
            .getOptimalSecondaryBorrowAmount(
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
            uint256[2] memory tokensTransferred = NOTIONAL
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
        uint256 lowerLimit = (optimalSecondaryAmount *
            SECONDARY_BORROW_LOWER_LIMIT) / 100;
        uint256 upperLimit = (optimalSecondaryAmount *
            SECONDARY_BORROW_UPPER_LIMIT) / 100;
        if (
            borrowedSecondaryAmount < lowerLimit ||
            upperLimit < borrowedSecondaryAmount
        ) {
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
            context: _poolContext(),
            maxPrimaryAmount: primaryAmount,
            maxSecondaryAmount: borrowedSecondaryAmount,
            minBPT: minBPT
        });
        uint256 balanceAfter = BALANCER_POOL_TOKEN.balanceOf(address(this));

        bptAmount = balanceAfter - balanceBefore;

        uint256 totalBPTSupply = BALANCER_POOL_TOKEN.totalSupply();
        uint256 totalBPTHeld = _bptHeld() + bptAmount;
        uint256 bptThreshold = _bptThreshold(totalBPTSupply);

        if (totalBPTHeld > bptThreshold)
            revert BalancerPoolShareTooHigh(totalBPTHeld, bptThreshold);

        LIQUIDITY_GAUGE.deposit(bptAmount);
        // Transfer gauge token to VeBALDelegator
        BOOST_CONTROLLER.depositToken(address(LIQUIDITY_GAUGE), bptAmount);
    }

    function _exitPool(
        PoolContext memory context,
        uint256 bptExitAmount,
        uint256 maturity,
        // @audit We need to validate that the spot price is within some band of the
        // oracle price before we exit here, we cannot trust that these minPrimary / minSecondary
        // values are correctly specified
        uint256 minPrimary,
        uint256 minSecondary
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        primaryBalance = TokenUtils.tokenBalance(context.primaryToken);
        secondaryBalance = TokenUtils.tokenBalance(context.secondaryToken);

        BalancerUtils.exitPoolExactBPTIn(
            context,
            minPrimary,
            minSecondary,
            bptExitAmount
        );

        primaryBalance =
            TokenUtils.tokenBalance(context.primaryToken) -
            primaryBalance;
        secondaryBalance =
            TokenUtils.tokenBalance(context.secondaryToken) -
            secondaryBalance;
    }

    function _unstakeBPT(BoostContext memory context, uint256 bptAmount)
        private
    {
        // Withdraw gauge token from VeBALDelegator
        context.boostController.withdrawToken(
            address(context.liquidityGauge),
            bptAmount
        );

        // Unstake BPT
        context.liquidityGauge.withdraw(bptAmount, false);
    }

    function redeemFromNotional(
        VaultContext memory context,
        uint256 bptClaim,
        uint256 maturity,
        RedeemParams memory params
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        _unstakeBPT(context.boostContext, bptClaim);

        return
            _exitPool(
                context.poolContext,
                bptClaim,
                maturity,
                params.minPrimary,
                params.minSecondary
            );
    }

    function repaySecondaryBorrow(
        address account,
        uint16 secondaryBorrowCurrencyId,
        uint256 maturity,
        uint256 debtSharesToRepay,
        uint32 secondarySlippageLimit,
        bytes memory callbackData,
        uint256 primaryBalance,
        uint256 secondaryBalance
    ) internal returns (uint256 underlyingAmount) {
        bytes memory returnData = Constants
            .NOTIONAL
            .repaySecondaryCurrencyFromVault(
                account,
                secondaryBorrowCurrencyId,
                maturity,
                debtSharesToRepay,
                secondarySlippageLimit,
                abi.encode(callbackData, secondaryBalance)
            );

        // positive = primaryAmount increased (residual secondary => primary)
        // negative = primaryAmount decreased (primary => secondary shortfall)
        int256 primaryAmountDiff = abi.decode(returnData, (int256));

        // @audit there is an edge condition here where the repay secondary currency from
        // vault sells more primary than is available in the current maturity. I'm not sure
        // how this can actually occur in practice but something to be mindful of.
        underlyingAmount = (primaryBalance.toInt() + primaryAmountDiff).toUint();
    }

    function handleRepaySecondaryBorrowCallback(
        uint256 underlyingRequired,
        bytes calldata data,
        ITradingModule tradingModule,
        address primaryToken,
        address secondaryToken,
        uint16 secondaryBorrowCurrencyId
    ) internal returns (bytes memory returnData) {
        // prettier-ignore
        (
            RepaySecondaryCallbackParams memory params,
            // secondaryBalance = secondary token amount from BPT redemption
            uint256 secondaryBalance
        ) = abi.decode(data, (RepaySecondaryCallbackParams, uint256));

        Trade memory trade;
        int256 primaryBalanceBefore = TokenUtils
            .tokenBalance(primaryToken)
            .toInt();

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

            trade = Trade(
                TradeType.EXACT_OUT_SINGLE,
                primaryToken,
                secondaryToken,
                secondaryShortfall,
                TradeHandler.getLimitAmount(
                    address(tradingModule),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    primaryToken,
                    secondaryToken,
                    secondaryShortfall,
                    params.slippageLimitBPS
                ),
                block.timestamp, // deadline
                params.exchangeData
            );

            trade.execute(tradingModule, params.dexId);

            // Setting secondaryBalance to 0 here because it should be
            // equal to underlyingRequired after the trade (validated by the TradingModule)
            // and 0 after the repayment token transfer.
            // Updating it here before the transfer
            secondaryBalance = 0;
        }

        // Transfer required secondary balance to Notional
        if (secondaryBorrowCurrencyId == Constants.ETH_CURRENCY_ID) {
            payable(address(Constants.NOTIONAL)).transfer(underlyingRequired);
        } else {
            IERC20(secondaryToken).checkTransfer(
                address(Constants.NOTIONAL),
                underlyingRequired
            );
        }

        if (secondaryBalance > 0) {
            // Sell residual secondary balance
            trade = Trade(
                TradeType.EXACT_IN_SINGLE,
                secondaryToken,
                primaryToken,
                secondaryBalance,
                TradeHandler.getLimitAmount(
                    address(tradingModule),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    secondaryToken,
                    primaryToken,
                    secondaryBalance,
                    params.slippageLimitBPS
                ),
                block.timestamp, // deadline
                params.exchangeData
            );

            trade.execute(tradingModule, params.dexId);
        }

        int256 primaryBalanceAfter = TokenUtils
            .tokenBalance(primaryToken)
            .toInt();

        // Return primaryBalanceDiff
        // If primaryBalanceAfter > primaryBalanceBefore, residual secondary currency was
        // sold for primary currency
        // If primaryBalanceBefore > primaryBalanceAfter, primary currency was sold
        // for secondary currency to cover the shortfall
        return abi.encode(primaryBalanceAfter - primaryBalanceBefore);
    }

    function _poolContext() internal view returns (PoolContext memory) {
        return
            PoolContext({
                pool: BALANCER_POOL_TOKEN,
                poolId: BALANCER_POOL_ID,
                primaryToken: address(_underlyingToken()),
                secondaryToken: address(SECONDARY_TOKEN),
                primaryIndex: PRIMARY_INDEX
            });
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE, VeBal Delegator and the contract itself
    function _bptHeld() internal view returns (uint256) {
        return
            VEBAL_DELEGATOR.getTokenBalance(
                address(LIQUIDITY_GAUGE),
                address(this)
            );
    }

    function _bptThreshold(uint256 totalBPTSupply)
        internal
        view
        returns (uint256)
    {
        return
            (totalBPTSupply * vaultSettings.maxBalancerPoolShare) /
            Constants.VAULT_PERCENT_BASIS;
    }
}
