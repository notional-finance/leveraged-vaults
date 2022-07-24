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
    Weighted2TokenOracleContext,
    TwoTokenPoolContext,
    Weighted2TokenAuraStrategyContext,
    StrategyContext,
    StrategyVaultState,
    StrategyVaultSettings
} from "./BalancerVaultTypes.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {NotionalUtils} from "../../utils/NotionalUtils.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {BalancerUtils} from "./internal/BalancerUtils.sol";
import {SecondaryBorrowUtils} from "./internal/SecondaryBorrowUtils.sol";
import {VaultUtils} from "./internal/VaultUtils.sol";
import {Weighted2TokenOracleMath} from "./internal/Weighted2TokenOracleMath.sol";
import {SettlementHelper} from "./SettlementHelper.sol";
import {BaseVaultStorage} from "./BaseVaultStorage.sol";
import {Weighted2TokenVaultMixin} from "./mixins/Weighted2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./mixins/AuraStakingMixin.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";

abstract contract Weighted2TokenVaultHelper is 
    BaseVaultStorage, 
    Weighted2TokenVaultMixin,
    AuraStakingMixin
{
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;
    using TradeHandler for Trade;

    event VaultSettlement(
        uint256 maturity,
        uint256 bptSettled,
        uint256 strategyTokensRedeemed,
        bool completedSettlement
    );

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

        uint256 debtSharesToRepay;
        uint256 borrowedSecondaryfCashAmount;
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            (debtSharesToRepay, borrowedSecondaryfCashAmount) = SecondaryBorrowUtils._getDebtSharesToRepay(
                SECONDARY_BORROW_CURRENCY_ID, address(this), maturity, redeemStrategyTokenAmount
            );
        }

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
            oracleContext: _weighted2TokenOracleContext(),
            stakingContext: _auraStakingContext(),
            baseContext: StrategyContext({
                totalBPTHeld: _bptHeld(),
                secondaryBorrowCurrencyId: SECONDARY_BORROW_CURRENCY_ID,
                tradingModule: TRADING_MODULE,
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
