// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolContext, 
    BoostContext,
    OracleContext,
    DepositParams,
    RedeemParams,
    SecondaryTradeParams,
    NormalSettlementContext,
    SettlementState
} from "./BalancerVaultTypes.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {SettlementHelper} from "./SettlementHelper.sol";
import {BalancerVaultStorage} from "./BalancerVaultStorage.sol";
import {Constants} from "../../global/Constants.sol";
import {VaultState} from "../../global/Types.sol";
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
    error BalancerPoolShareTooHigh(uint256 totalBPTHeld, uint256 bptThreshold);
    error InvalidMinAmounts(uint256 pairPrice, uint256 minPrimary, uint256 minSecondary);

    event VaultSettlement(
        uint256 maturity,
        uint256 bptSettled,
        uint256 strategyTokensRedeemed,
        bool completedSettlement
    );

    function _getOraclePairPrice() internal view returns (uint256) {
        return BalancerUtils.getOraclePairPrice({
            context: _oracleContext(),
            balancerOracleWeight: vaultSettings.balancerOracleWeight,
            baseToken: address(_underlyingToken()),
            quoteToken: address(SECONDARY_TOKEN),
            tradingModule: TRADING_MODULE
        });
    }

    /// @notice Validates the min Balancer exit amounts against the price oracle.
    /// These values are passed in as parameters. So, we must validate them.
    function _validateMinExitAmounts(uint256 minPrimary, uint256 minSecondary) internal view {
        (uint256 normalizedPrimary, uint256 normalizedSecondary) = BalancerUtils._normalizeBalances(
            minPrimary, PRIMARY_DECIMALS, minSecondary, SECONDARY_DECIMALS
        );
        uint256 pairPrice = _getOraclePairPrice();
        uint256 calculatedPairPrice = normalizedSecondary * BalancerUtils.BALANCER_PRECISION / 
            normalizedPrimary;

        uint256 lowerLimit = (pairPrice * Constants.MIN_EXIT_AMOUNTS_LOWER_LIMIT) / 100;
        uint256 upperLimit = (pairPrice * Constants.MIN_EXIT_AMOUNTS_UPPER_LIMIT) / 100;
        if (calculatedPairPrice < lowerLimit || upperLimit < calculatedPairPrice) {
            revert InvalidMinAmounts(pairPrice, minPrimary, minSecondary);
        }
    }

    function _borrowSecondaryCurrency(
        address account,
        uint256 maturity,
        uint256 primaryAmount,
        DepositParams memory params
    ) internal returns (uint256 borrowedSecondaryAmount) {
        // If secondary currency is not specified then return
        if (SECONDARY_BORROW_CURRENCY_ID == 0) return 0;

        uint256 optimalSecondaryAmount = BalancerUtils
            .getOptimalSecondaryBorrowAmount(_oracleContext(), primaryAmount);

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

        // Check BPT threshold to make sure our share of the pool is
        // below maxBalancerPoolShare
        uint256 totalBPTSupply = BALANCER_POOL_TOKEN.totalSupply();
        uint256 totalBPTHeld = _bptHeld() + bptAmount;
        uint256 bptThreshold = _bptThreshold(totalBPTSupply);

        if (totalBPTHeld > bptThreshold)
            revert BalancerPoolShareTooHigh(totalBPTHeld, bptThreshold);

        LIQUIDITY_GAUGE.deposit(bptAmount);
        // Transfer gauge token to VeBALDelegator
        BOOST_CONTROLLER.depositToken(address(LIQUIDITY_GAUGE), bptAmount);
    }

    function repaySecondaryBorrow(
        address account,
        uint256 maturity,
        uint256 debtSharesToRepay,
        RedeemParams memory params,
        uint256 secondaryBalance,
        uint256 primaryBalance
    ) internal returns (uint256 finalPrimaryBalance) {
        bytes memory returnData = NOTIONAL.repaySecondaryCurrencyFromVault(
            account,
            SECONDARY_BORROW_CURRENCY_ID,
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
                0,
                block.timestamp, // deadline
                params.exchangeData
            );

            _executeTradeWithDynamicSlippage(params.dexId, trade, params.oracleSlippagePercent);

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
            0,
            block.timestamp, // deadline
            params.exchangeData
        );

        (/* */, primaryPurchased) = _executeTradeWithDynamicSlippage(
            params.dexId, trade, params.oracleSlippagePercent
        );
    }

    /// @notice Gets the amount of debt shares needed to pay off the secondary debt
    /// @param account account address
    /// @param maturity maturity timestamp
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return debtSharesToRepay amount of secondary debt shares
    /// @return borrowedSecondaryfCashAmount amount of secondary fCash borrowed
    function getDebtSharesToRepay(address account, uint256 maturity, uint256 strategyTokenAmount)
        internal view returns (
            uint256 debtSharesToRepay,
            uint256 borrowedSecondaryfCashAmount
    ) {
        if (SECONDARY_BORROW_CURRENCY_ID == 0) return (0, 0);

        // prettier-ignore
        (uint256 totalfCashBorrowed, uint256 totalAccountDebtShares) = NOTIONAL.getSecondaryBorrow(
            address(this), SECONDARY_BORROW_CURRENCY_ID, maturity
        );
        uint256 _totalSupply = _totalSupplyInMaturity(maturity);

        if (account == address(this)) {
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
            ) = NOTIONAL.getVaultAccountDebtShares(account, address(this));

            debtSharesToRepay =
                (accountDebtShares[0] * strategyTokenAmount) / accountStrategyTokens;
            borrowedSecondaryfCashAmount =
                (debtSharesToRepay * totalfCashBorrowed) / totalAccountDebtShares;
        }
    }

    function _repayPrimaryDebt(
        NormalSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        int256 primaryBalance
    ) private returns (bool settled, uint256 primaryBalancePostSettlement) {
        // Check if we have enough to pay the primary debt off
        if (primaryBalance < context.underlyingCashRequiredToSettle) {
            // Not enough to repay, let the balance acumulate in this contract
            // settled = false
            primaryBalancePostSettlement = primaryBalance.toUint();
        } else {
            if (primaryBalance > 0) {
                // Calculate the amount of surplus cash after primary repayment
                // If underlyingCashRequiredToSettle < 0, that means there is excess
                // cash in the system. We add it to the surplus with the subtraction.
                int256 surplus = primaryBalance - context.underlyingCashRequiredToSettle;
    
                // Make sure we are not settling too much because we want
                // to preserve as much BPT as possible
                if (surplus > vaultSettings.maxUnderlyingSurplus.toInt()) {
                    revert SettlementHelper.RedeemingTooMuch(
                        primaryBalance,
                        context.underlyingCashRequiredToSettle
                    );
                }

                // Call redeemStrategyTokensToCash with a special payload
                // to handle primary repayment
                Constants.NOTIONAL.redeemStrategyTokensToCash(
                    maturity, 
                    strategyTokensToRedeem,
                    abi.encode(primaryBalance.toUint())
                );
            }

            // primaryBalancePostSettlement = 0
            settled = true;
        }
    }

    /// @notice Executes a normal vault settlement where BPT tokens are redeemed and returned tokens
    /// are traded accordingly
    /// @param maturity the maturity to settle
    /// @param strategyTokensToRedeem number of strategy tokens to redeem, 
    /// we do not authenticate this amount, only the slippage
    /// from minPrimary and minSecondary
    function _executeNormalSettlement(
        SettlementState memory state,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) internal returns (bool completedSettlement) {
        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        _validateMinExitAmounts(params.minPrimary, params.minSecondary);

        uint256 bptToSettle = _convertStrategyTokensToBPTClaim(strategyTokensToRedeem, maturity);
        NormalSettlementContext memory context = _normalSettlementContext(
            state, maturity, strategyTokensToRedeem);

        // Exits BPT tokens from the pool and returns the most up to date balances
        (
            bool hasSufficientBalanceToSettle, 
            uint256 primaryBalance, 
            uint256 secondaryBalance
        ) = SettlementHelper._settleVaultNormal(context, bptToSettle, params);

        if (hasSufficientBalanceToSettle) {
            // Settle secondary currency first
            if (context.borrowedSecondaryfCashAmountExternal > 0) {
                // This method call will trade any primary balance into secondary to repay or it will
                // trade any excess secondary back into the primary currency
                primaryBalance = repaySecondaryBorrow(
                    address(this),
                    maturity,
                    context.debtSharesToRepay,
                    params,
                    secondaryBalance,
                    primaryBalance
                );

                // Secondary balance should be 0 after repayment
                // Any residual balance should've been sold for primary currency
                secondaryBalance = 0;
            }

            // Settle primary currency with updated primaryBalance (from secondary currency trading)
            (completedSettlement, primaryBalance) = _repayPrimaryDebt(
                context, maturity, strategyTokensToRedeem, primaryBalance.toInt());
        }

        // Mark the vault as settled
        if (maturity <= block.timestamp) {
            Constants.NOTIONAL.settleVault(address(this), maturity);
        }

        // Update settlement balances and strategy tokens redeemed
        settlementState[maturity] = SettlementState(
            primaryBalance, 
            secondaryBalance, 
            state.strategyTokensRedeemed + strategyTokensToRedeem
        );

        emit VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem, completedSettlement);
    }

    function _normalSettlementContext(
        SettlementState memory state,
        uint256 maturity,
        uint256 redeemStrategyTokenAmount
    ) private returns (NormalSettlementContext memory) {
        // Get primary and secondary debt amounts from Notional
        // prettier-ignore
        (
            /* int256 assetCashRequiredToSettle */,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        // prettier-ignore
        (
            uint256 debtSharesToRepay,
            uint256 borrowedSecondaryfCashAmount
        ) = getDebtSharesToRepay(address(this), maturity, redeemStrategyTokenAmount);

        // If underlyingCashRequiredToSettle is 0 (no debt) or negative (surplus cash)
        // and borrowedSecondaryfCashAmount is also 0, no settlement is required
        if (
            underlyingCashRequiredToSettle <= 0 &&
            borrowedSecondaryfCashAmount == 0
        ) {
            revert SettlementHelper.SettlementNotRequired(); /// @dev no debt
        }

        // Convert fCash to secondary currency precision
        borrowedSecondaryfCashAmount =
            (borrowedSecondaryfCashAmount * (10**SECONDARY_DECIMALS)) /
            uint256(Constants.INTERNAL_TOKEN_PRECISION);

        return
            NormalSettlementContext({
                maxUnderlyingSurplus: vaultSettings.maxUnderlyingSurplus,
                primarySettlementBalance: state.primarySettlementBalance,
                secondarySettlementBalance: state.secondarySettlementBalance,
                redeemStrategyTokenAmount: redeemStrategyTokenAmount,
                debtSharesToRepay: debtSharesToRepay,
                underlyingCashRequiredToSettle: underlyingCashRequiredToSettle,
                borrowedSecondaryfCashAmountExternal: borrowedSecondaryfCashAmount,
                poolContext: _poolContext(),
                boostContext: _boostContext()
            });
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

    function _boostContext() internal view returns (BoostContext memory) {
        return BoostContext(LIQUIDITY_GAUGE, BOOST_CONTROLLER);
    }

    function _oracleContext() internal view returns (OracleContext memory) {
        return OracleContext({
            pool: BALANCER_POOL_TOKEN,
            poolId: BALANCER_POOL_ID,
            oracleWindowInSeconds: vaultSettings.oracleWindowInSeconds,
            primaryWeight: PRIMARY_WEIGHT,
            secondaryWeight: SECONDARY_WEIGHT,
            primaryIndex: PRIMARY_INDEX,
            primaryDecimals: PRIMARY_DECIMALS,
            secondaryDecimals: SECONDARY_DECIMALS
        });
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE, VeBal Delegator and the contract itself
    function _bptHeld() internal view returns (uint256) {
        return VEBAL_DELEGATOR.getTokenBalance(address(LIQUIDITY_GAUGE), address(this));
    }

    function _bptThreshold(uint256 totalBPTSupply) internal view returns (uint256) {
        return (totalBPTSupply * vaultSettings.maxBalancerPoolShare) / Constants.VAULT_PERCENT_BASIS;
    }

    function _totalSupplyInMaturity(uint256 maturity) internal view returns (uint256) {
        VaultState memory state = NOTIONAL.getVaultState(address(this), maturity);
        return state.totalStrategyTokens;
    }

    function _getBPTHeldInMaturity(uint256 maturity) internal view returns (
        uint256 bptHeldInMaturity,
        uint256 totalStrategyTokenSupplyInMaturity
    ) {
        uint256 totalBPTHeld = _bptHeld();
        totalStrategyTokenSupplyInMaturity = _totalSupplyInMaturity(maturity);
        bptHeldInMaturity =
            (totalBPTHeld * totalStrategyTokenSupplyInMaturity) /
            vaultState.totalStrategyTokenGlobal;
    }

    /// @notice Converts BPT to strategy tokens
    function _convertBPTClaimToStrategyTokens(uint256 bptClaim, uint256 maturity)
        internal view returns (uint256 strategyTokenAmount) {
        if (vaultState.totalStrategyTokenGlobal == 0) {
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        //prettier-ignore
        (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        strategyTokenAmount =
            (totalStrategyTokenSupplyInMaturity * bptClaim) /
            bptHeldInMaturity;
    }

    /// @notice Converts strategy tokens to BPT
    function _convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount, uint256 maturity) 
        internal view returns (uint256 bptClaim) {
        if (vaultState.totalStrategyTokenGlobal == 0)
            return strategyTokenAmount;

        //prettier-ignore
        (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        bptClaim =
            (bptHeldInMaturity * strategyTokenAmount) /
            totalStrategyTokenSupplyInMaturity;
    }
}
