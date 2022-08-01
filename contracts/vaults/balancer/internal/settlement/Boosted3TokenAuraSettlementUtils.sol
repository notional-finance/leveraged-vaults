// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext, 
    SettlementState, 
    BoostedSettlementData,
    RedeemParams,
    StrategyContext,
    ThreeTokenPoolContext,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {Constants} from "../../../../global/Constants.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {Errors} from "../../../../global/Errors.sol";
import {SettlementUtils} from "./SettlementUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";

library Boosted3TokenAuraSettlementUtils {
    using SafeInt256 for uint256;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using VaultUtils for StrategyVaultState;
    using VaultUtils for SettlementState;

    /// @notice Executes a normal vault settlement where BPT tokens are redeemed and returned tokens
    /// are traded accordingly
    /// @param maturity the maturity to settle
    /// @param strategyTokensToRedeem number of strategy tokens to redeem, 
    /// we do not authenticate this amount, only the slippage
    /// from minPrimary and minSecondary
    function _executeNormalSettlement(
        Boosted3TokenAuraStrategyContext memory context,
        SettlementState memory state,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        RedeemParams memory params
    ) internal returns (bool completedSettlement) {
        require(strategyTokensToRedeem <= type(uint80).max); /// @dev strategyTokensToRedeem overflow

        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        // TODO: implement minPrimary validation
        /*context.poolContext._validateMinExitAmounts({
            oracleContext: context.oracleContext,
            tradingModule: context.strategyContext.tradingModule,
            minPrimary: params.minPrimary,
            minSecondary: params.minSecondary
        });*/

        uint256 bptToSettle = context.baseStrategy._convertStrategyTokensToBPTClaim(
            strategyTokensToRedeem, maturity
        );

        BoostedSettlementData memory data = _boostedSettlementData({
            strategyContext: context.baseStrategy,
            state: state,
            maturity: maturity,
            redeemStrategyTokenAmount: strategyTokensToRedeem
        });

        // Update totalStrategyTokenGlobal in storage to keep it in sync
        // with _bptHeld() after we unstake and exit
        context.baseStrategy.vaultState.totalStrategyTokenGlobal -= uint80(strategyTokensToRedeem);
        context.baseStrategy.vaultState._setStrategyVaultState();

        // Exits BPT tokens from the pool and returns the most up to date balances
        uint256 primaryBalance;
        (
            completedSettlement,
            primaryBalance
        ) = _exitAndSettle(context, data, bptToSettle, maturity, params);

        // Mark the vault as settled
        if (maturity <= block.timestamp) {
            Constants.NOTIONAL.settleVault(address(this), maturity);
        }

        require(primaryBalance <= type(uint88).max); /// @dev primaryBalance overflow

        // Update settlement balances and strategy tokens redeemed
        SettlementState(
            uint88(primaryBalance), 
            0, 
            state.strategyTokensRedeemed + uint80(strategyTokensToRedeem)
        )._setSettlementState(maturity);

        emit SettlementUtils.VaultSettlement(maturity, bptToSettle, strategyTokensToRedeem, completedSettlement); 
    }

    /// @notice Redeems BPTs from the pool and checks if there is sufficient balance to settle on
    /// either one of the primary or secondary balances
    function _exitAndSettle(
        Boosted3TokenAuraStrategyContext memory context,
        BoostedSettlementData memory data,
        uint256 bptToSettle,
        uint256 maturity,
        RedeemParams memory params
    ) private returns (bool completedSettlement, uint256 primaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        context.stakingContext.auraRewardPool.withdrawAndUnwrap(bptToSettle, false); // claimRewards = false
        
        /// @notice minPrimary is validated before this function is called
        primaryBalance = context.poolContext._exitPoolExactBPTIn(bptToSettle, params.minPrimary);
        primaryBalance += data.primarySettlementBalance;

        // We can settle if we have enough to pay off either the primary side or the secondary size
        bool hasSufficientBalanceToSettle = data.underlyingCashRequiredToSettle <= primaryBalance.toInt();

        if (hasSufficientBalanceToSettle) {
            // Settle primary currency with updated primaryBalance (from secondary currency trading)
            (completedSettlement, primaryBalance) = SettlementUtils._repayPrimaryDebt({
                underlyingCashRequiredToSettle: data.underlyingCashRequiredToSettle,
                maxUnderlyingSurplus: data.maxUnderlyingSurplus,
                redeemStrategyTokenAmount: data.redeemStrategyTokenAmount,
                maturity: maturity,
                primaryBalance: primaryBalance.toInt()
            });
        }
    }

    function _boostedSettlementData(
        StrategyContext memory strategyContext,
        SettlementState memory state,
        uint256 maturity,
        uint256 redeemStrategyTokenAmount
    ) private view returns (BoostedSettlementData memory) {
        // Get primary and secondary debt amounts from Notional
        // prettier-ignore
        (
            /* int256 assetCashRequiredToSettle */,
            int256 underlyingCashRequiredToSettle
        ) = Constants.NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        // If underlyingCashRequiredToSettle is 0 (no debt) or negative (surplus cash)
        // no settlement is required
        if (underlyingCashRequiredToSettle <= 0) {
            revert Errors.SettlementNotRequired(); /// @dev no debt
        }

        return
            BoostedSettlementData({
                maxUnderlyingSurplus: strategyContext.vaultSettings.maxUnderlyingSurplus,
                primarySettlementBalance: state.primarySettlementBalance,
                redeemStrategyTokenAmount: redeemStrategyTokenAmount,
                underlyingCashRequiredToSettle: underlyingCashRequiredToSettle
            });
    }
}
