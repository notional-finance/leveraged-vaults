// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;

import {TokenUtils} from "../../utils/TokenUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";

library VaultHelper {
    using TradeHandler for Trade;
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    /// @notice Precision for all percentages, 1e4 = 100% (i.e. settlementSlippageLimit)
    uint16 internal constant VAULT_PERCENTAGE_PRECISION = 1e4;
    uint16 internal constant BALANCER_POOL_SHARE_BUFFER = 8e3; // 1e4 = 100%, 8e3 = 80%

    error InvalidSecondaryBorrow(
        uint256 borrowedSecondaryAmount,
        uint256 optimalSecondaryAmount,
        uint256 secondaryfCashAmount
    );

    struct DepositParams {
        uint256 minBPT;
        uint256 secondaryfCashAmount;
        uint32 secondarySlippageLimit;
    }

    struct RedeemParams {
        uint32 secondarySlippageLimit;
        uint256 minPrimary;
        uint256 minSecondary;
        bytes callbackData;
    }

    struct RepaySecondaryCallbackParams {
        uint16 dexId;
        uint32 slippageLimit; // @audit the denomination of this should be marked in the variable name
        bytes exchangeData;
    }

    struct BoostContext {
        ILiquidityGauge liquidityGauge;
        IBoostController boostController;
    }

    struct VaultContext {
        PoolContext poolContext;
        BoostContext boostContext;
    }

    /// @notice Balancer pool related fields
    struct PoolContext {
        IBalancerPool pool;
        bytes32 poolId;
        address primaryToken;
        address secondaryToken;
        uint8 primaryIndex;
    }

    function borrowSecondaryCurrency(
        address account,
        uint256 deposit,
        uint256 maturity,
        uint256 secondaryfCashAmount,
        uint32 secondarySlippageLimit,
        uint256 optimalSecondaryAmount,
        uint256 secondaryBorrowLowerLimit,
        uint256 secondaryBorrowUpperLimit
    ) internal returns (uint256 borrowedSecondaryAmount) {
        // Borrow secondary currency from Notional (tokens will be transferred to this contract)
        {
            uint256[2] memory fCashToBorrow;
            uint32[2] memory maxBorrowRate;
            uint32[2] memory minRollLendRate;
            fCashToBorrow[0] = secondaryfCashAmount;
            maxBorrowRate[0] = secondarySlippageLimit;
            uint256[2] memory tokensTransferred = Constants
                .NOTIONAL
                .borrowSecondaryCurrencyToVault(
                    account,
                    maturity,
                    fCashToBorrow,
                    maxBorrowRate,
                    minRollLendRate
                );

            borrowedSecondaryAmount = tokensTransferred[0];
        }

        // Require the secondary borrow amount to be within SECONDARY_BORROW_LOWER_LIMIT percent
        // of the optimal amount
        if (
            // @audit rearrange these so that the inequalities are always <= for clarity.
            borrowedSecondaryAmount <
            ((optimalSecondaryAmount * (secondaryBorrowLowerLimit)) / 100) ||
            borrowedSecondaryAmount >
            (optimalSecondaryAmount * (secondaryBorrowUpperLimit)) / 100
        ) {
            revert InvalidSecondaryBorrow(
                borrowedSecondaryAmount,
                optimalSecondaryAmount,
                secondaryfCashAmount
            );
        }
    }

    function _joinPool(
        PoolContext memory context,
        uint256 deposit,
        uint256 borrowedSecondaryAmount,
        uint256 minBPT
    ) private returns (uint256 bptAmount) {
        // Join pool
        bptAmount = context.pool.balanceOf(address(this));
        BalancerUtils.joinPoolExactTokensIn(
            context.poolId,
            context.primaryToken,
            deposit,
            context.secondaryToken,
            borrowedSecondaryAmount,
            context.primaryIndex,
            minBPT
        );
        bptAmount = context.pool.balanceOf(address(this)) - bptAmount;

        // TODO: check maxBalancerPoolShare
    }

    function _stakeBPT(BoostContext memory context, uint256 bptAmount) private {
        // Stake liquidity
        context.liquidityGauge.deposit(bptAmount);

        // Transfer gauge token to VeBALDelegator
        context.boostController.depositToken(
            address(context.liquidityGauge),
            bptAmount
        );
    }

    function depositFromNotional(
        VaultContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        uint256 borrowedSecondaryAmount,
        uint256 minBPT,
        uint256 totalStrategyTokenGlobal,
        uint256 bptHeldInMaturity,
        uint256 totalStrategyTokenSupplyInMaturity
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 bptAmount = _joinPool(
            context.poolContext,
            deposit,
            borrowedSecondaryAmount,
            minBPT
        );

        _stakeBPT(context.boostContext, bptAmount);

        // Mint strategy tokens
        if (totalStrategyTokenGlobal == 0) {
            // @audit this needs to be returned in 8 decimal precision
            strategyTokensMinted = bptAmount;
        } else {
            //prettier-ignore
            strategyTokensMinted =
                (totalStrategyTokenSupplyInMaturity * bptAmount) /
                // @audit leave a comment on this math here, but looks correct
                (bptHeldInMaturity - bptAmount);
        }
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
            context.poolId,
            context.primaryToken,
            minPrimary,
            context.secondaryToken,
            minSecondary,
            context.primaryIndex,
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
            VaultHelper.RepaySecondaryCallbackParams memory params,
            // secondaryBalance = secondary token amount from BPT redemption
            uint256 secondaryBalance
        ) = abi.decode(data, (VaultHelper.RepaySecondaryCallbackParams, uint256));

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
                    params.slippageLimit
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
                    params.slippageLimit // @audit what denomination is slippage limit in here?
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
}
