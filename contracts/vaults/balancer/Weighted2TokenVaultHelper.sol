// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolContext,
    OracleContext,
    DepositParams,
    RedeemParams,
    SecondaryTradeParams,
    NormalSettlementContext,
    SettlementState,
    WeightedOracleContext,
    TwoTokenPoolContext,
    Weighted2TokenAuraStrategyContext,
    StrategyContext,
    StrategyVaultState,
    StrategyVaultSettings
} from "./BalancerVaultTypes.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {NotionalUtils} from "../../utils/NotionalUtils.sol";
import {BalancerUtils} from "./internal/BalancerUtils.sol";
import {SettlementHelper} from "./SettlementHelper.sol";
import {BaseVaultStorage} from "./BaseVaultStorage.sol";
import {Weighted2TokenVaultMixin} from "./mixins/Weighted2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./mixins/AuraStakingMixin.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";
import {VaultUtils} from "./internal/VaultUtils.sol";
import {Weighted2TokenOracleMath} from "./internal/Weighted2TokenOracleMath.sol";

abstract contract Weighted2TokenVaultHelper is 
    BaseVaultStorage, 
    Weighted2TokenVaultMixin,
    AuraStakingMixin
{
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    event VaultSettlement(
        uint256 maturity,
        uint256 bptSettled,
        uint256 strategyTokensRedeemed,
        bool completedSettlement
    );

    function _repaySecondaryBorrowCallback(
        address, /* secondaryToken */
        uint256 underlyingRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        require(SECONDARY_BORROW_CURRENCY_ID != 0); /// @dev invalid secondary currency

        (
            bytes memory tradeParams,
            // secondaryBalance = secondary token amount from BPT redemption
            uint256 secondaryBalance
        ) = abi.decode(data, (bytes, uint256));

        SecondaryTradeParams memory params = abi.decode(tradeParams, (SecondaryTradeParams));

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

            require(
                params.tradeType == TradeType.EXACT_OUT_SINGLE || params.tradeType == TradeType.EXACT_OUT_BATCH
            );

            Trade memory trade = Trade(
                params.tradeType,
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
        require(
            params.tradeType == TradeType.EXACT_IN_SINGLE || params.tradeType == TradeType.EXACT_IN_BATCH
        );

        // Sell residual secondary balance
        Trade memory trade = Trade(
            params.tradeType,
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
            ) = NOTIONAL.getVaultAccountDebtShares(account, address(this));

            debtSharesToRepay = accountStrategyTokens == 0 ? 0 :
                (accountDebtShares[0] * strategyTokenAmount) / accountStrategyTokens;
            borrowedSecondaryfCashAmount = totalAccountDebtShares == 0 ? 0 :
                (debtSharesToRepay * totalfCashBorrowed) / totalAccountDebtShares;
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
  /*      require(strategyTokensToRedeem <= type(uint80).max); /// @dev strategyTokensToRedeem overflow

        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        _validateMinExitAmounts(params.minPrimary, params.minSecondary);

        uint256 bptToSettle = _convertStrategyTokensToBPTClaim(strategyTokensToRedeem, maturity);
        NormalSettlementContext memory context = _normalSettlementContext(
            state, maturity, strategyTokensToRedeem);

        StrategyVaultState memory strategyVaultState = VaultUtils._getStrategyVaultState();
        strategyVaultState.totalStrategyTokenGlobal -= uint80(strategyTokensToRedeem);
        VaultUtils._setStrategyVaultState(strategyVaultState);

        // Exits BPT tokens from the pool and returns the most up to date balances
        uint256 primaryBalance;
        uint256 secondaryBalance;
        (
            completedSettlement,
            primaryBalance,
            secondaryBalance
        ) = SettlementHelper.settleVaultNormal(context, bptToSettle, maturity, params);

        // Mark the vault as settled
        if (maturity <= block.timestamp) {
            Constants.NOTIONAL.settleVault(address(this), maturity);
        }

        require(primaryBalance <= type(uint88).max); /// @dev primaryBalance overflow
        require(secondaryBalance <= type(uint88).max); /// @dev secondaryBalance overflow

        // Update settlement balances and strategy tokens redeemed
        VaultUtils._setSettlementState(maturity, SettlementState(
            uint88(primaryBalance), 
            uint88(secondaryBalance), 
            state.strategyTokensRedeemed + uint80(strategyTokensToRedeem)
        ));

        emit VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem, completedSettlement); */
    }

    function _normalSettlementContext(
        SettlementState memory state,
        uint256 maturity,
        uint256 redeemStrategyTokenAmount
    ) private view returns (NormalSettlementContext memory) {
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

        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
        return
            NormalSettlementContext({
                secondaryBorrowCurrencyId: SECONDARY_BORROW_CURRENCY_ID,
                maxUnderlyingSurplus: strategyVaultSettings.maxUnderlyingSurplus,
                primarySettlementBalance: state.primarySettlementBalance,
                secondarySettlementBalance: state.secondarySettlementBalance,
                redeemStrategyTokenAmount: redeemStrategyTokenAmount,
                debtSharesToRepay: debtSharesToRepay,
                underlyingCashRequiredToSettle: underlyingCashRequiredToSettle,
                borrowedSecondaryfCashAmountExternal: borrowedSecondaryfCashAmount,
                poolContext: _twoTokenPoolContext(),
                stakingContext: _auraStakingContext()
            });
    }

    function _strategyContext() internal view returns (Weighted2TokenAuraStrategyContext memory) {
        return Weighted2TokenAuraStrategyContext({
            poolContext: _twoTokenPoolContext(),
            oracleContext: _weightedOracleContext(),
            stakingContext: _auraStakingContext(),
            baseContext: StrategyContext({
                totalBPTHeld: _bptHeld(),
                secondaryBorrowCurrencyId: SECONDARY_BORROW_CURRENCY_ID,
                vaultSettings: VaultUtils._getStrategyVaultSettings(),
                vaultState: VaultUtils._getStrategyVaultState()
            })
        });
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return AURA_REWARD_POOL.balanceOf(address(this));
    }
}
