// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolParams,
    DepositParams,
    DepositTradeParams,
    RedeemParams,
    SecondaryTradeParams,
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    OracleContext
} from "../BalancerVaultTypes.sol";
import {SafeInt256} from "../../../global/SafeInt256.sol";
import {TradeHandler} from "../../../trading/TradeHandler.sol";
import {AuraStakingUtils} from "./AuraStakingUtils.sol";
import {VaultUtils} from "./VaultUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {SecondaryBorrowUtils} from "./SecondaryBorrowUtils.sol";
import {Constants} from "../../../global/Constants.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {ITradingModule, Trade} from "../../../../interfaces/trading/ITradingModule.sol";

library TwoTokenAuraStrategyUtils {
    using TradeHandler for Trade;
    using SafeInt256 for uint256;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    /// @notice Trade primary currency for secondary if the trade is specified
    function _tradePrimaryForSecondary(ITradingModule tradingModule, bytes memory data) private {
        (DepositTradeParams memory params) = abi.decode(data, (DepositTradeParams));
        params.trade._executeTradeWithStaticSlippage(params.dexId, tradingModule);
    }

    function _deposit(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        uint256 deposit,
        uint256 maturity,
        uint256 borrowedSecondaryAmount,
        DepositParams memory params
    ) internal returns (uint256 strategyTokensMinted) {
        if (params.tradeData.length != 0) {
            _tradePrimaryForSecondary(strategyContext.tradingModule, params.tradeData);
        }

        uint256 bptMinted = strategyContext._joinPoolAndStake({
            stakingContext: stakingContext,
            poolContext: poolContext,
            primaryAmount: deposit,
            secondaryAmount: borrowedSecondaryAmount,
            minBPT: params.minBPT
        });

        // Update _bptHeld() in memory
        strategyContext.totalBPTHeld += bptMinted;

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(bptMinted, maturity);
        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        strategyContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        strategyContext.vaultState._setStrategyVaultState(); 
    }

    function _redeem(
        StrategyContext memory strategyContext,
        OracleContext memory oracleContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        RedeemParams memory params
    ) internal returns (uint256 finalPrimaryBalance) {
        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        // TODO: Is this check necessary if account != address(this)?
        poolContext._validateMinExitAmounts({
            oracleContext: oracleContext,
            tradingModule: strategyContext.tradingModule,
            minPrimary: params.minPrimary,
            minSecondary: params.minSecondary
        });

        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokens, maturity);

        if (bptClaim == 0) return 0;

        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance)
            = TwoTokenAuraStrategyUtils._unstakeAndExitPoolExactBPTIn(
                stakingContext, poolContext, bptClaim, params.minPrimary, params.minSecondary
            );

        // Update _bptHeld() in memory
        strategyContext.totalBPTHeld -= bptClaim;

        if (strategyContext.secondaryBorrowCurrencyId != 0) {
            // Returns the amount of secondary debt shares that need to be repaid
            (uint256 debtSharesToRepay, /*  */) = SecondaryBorrowUtils._getDebtSharesToRepay(
                strategyContext.secondaryBorrowCurrencyId, account, maturity, strategyTokens
            );

            finalPrimaryBalance = SecondaryBorrowUtils._repaySecondaryBorrow({
                secondaryBorrowCurrencyId: strategyContext.secondaryBorrowCurrencyId,
                account: account,
                maturity: maturity,
                debtSharesToRepay: debtSharesToRepay,
                params: params,
                secondaryBalance: secondaryBalance,
                primaryBalance: primaryBalance
            });
        } else if (secondaryBalance > 0) {
            // If there is no secondary debt, we still need to sell the secondary balance
            // back to the primary token here.
            (SecondaryTradeParams memory tradeParams) = abi.decode(
                params.secondaryTradeParams, (SecondaryTradeParams)
            );
            uint256 primaryPurchased = SecondaryBorrowUtils._sellSecondaryBalance(
                tradeParams, 
                strategyContext.tradingModule, 
                poolContext.primaryToken, 
                poolContext.primaryToken, 
                secondaryBalance
            );

            finalPrimaryBalance = primaryBalance + primaryPurchased;
        }

        // Update global strategy token balance
        // This only needs to be updated for normal redemption
        // and emergency settlement. For normal and post-maturity settlement
        // scenarios (account == address(this) && data.length == 32), we
        // update totalStrategyTokenGlobal before this function is called.
        strategyContext.vaultState.totalStrategyTokenGlobal -= uint80(strategyTokens);
        strategyContext.vaultState._setStrategyVaultState(); 
    }

    function _joinPoolAndStake(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        // prettier-ignore
        PoolParams memory poolParams = poolContext._getPoolParams( 
            primaryAmount, 
            secondaryAmount,
            true // isJoin
        );

        // Join the balancer pool and stake the tokens for boosting
        bptMinted = stakingContext._joinPoolAndStake({
            poolContext: poolContext.baseContext,
            poolParams: poolParams,
            totalBPTHeld: strategyContext.totalBPTHeld,
            bptThreshold: strategyContext.vaultSettings._bptThreshold(
                poolContext.baseContext.pool.totalSupply()
            ),
            minBPT: minBPT
        });
    }

    function _unstakeAndExitPoolExactBPTIn(
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        uint256 bptClaim,
        uint256 minPrimary,
        uint256 minSecondary
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        uint256[] memory exitBalances = AuraStakingUtils._unstakeAndExitPoolExactBPTIn({
            stakingContext: stakingContext, 
            poolContext: poolContext.baseContext,
            poolParams: poolContext._getPoolParams(minPrimary, minSecondary, false), // isJoin = false
            bptExitAmount: bptClaim
        });

        (primaryBalance, secondaryBalance) 
            = (exitBalances[poolContext.primaryIndex], exitBalances[poolContext.secondaryIndex]);
    }

    /// @notice Converts strategy tokens to BPT
    function _convertStrategyTokensToBPTClaim(
        StrategyContext memory context,
        uint256 strategyTokenAmount, 
        uint256 maturity
    ) internal view returns (uint256 bptClaim) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0)
            return strategyTokenAmount;

        uint256 totalSupplyInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);
        bptClaim = (bptHeldInMaturity * strategyTokenAmount) / totalSupplyInMaturity;
    }

    /// @notice Converts BPT to strategy tokens
    function _convertBPTClaimToStrategyTokens(
        StrategyContext memory context,
        uint256 bptClaim, 
        uint256 maturity
    ) internal view returns (uint256 strategyTokenAmount) {
        StrategyVaultState memory state = context.vaultState;
        if (state.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            return (bptClaim * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / 
                BalancerUtils.BALANCER_PRECISION;
        }

        uint256 totalSupplyInMaturity = NotionalUtils._totalSupplyInMaturity(maturity);
        uint256 bptHeldInMaturity = state._getBPTHeldInMaturity(totalSupplyInMaturity, context.totalBPTHeld);

        // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
        // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
        // The precision here will be the same as strategy token supply.
        strategyTokenAmount = (bptClaim * totalSupplyInMaturity) / bptHeldInMaturity;
    }

    function _convertStrategyToUnderlying(
        StrategyContext memory strategyContext,
        OracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) internal view returns (int256 underlyingValue) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(
            strategyTokenAmount, maturity
        );

        uint256 primaryBalance = poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, bptClaim
        );

        if (strategyContext.secondaryBorrowCurrencyId == 0) return primaryBalance.toInt();

        // Oracle price for the pair in 18 decimals
        uint256 oraclePairPrice = poolContext._getOraclePairPrice(
            oracleContext, strategyContext.tradingModule
        );

        // prettier-ignore
        (
            /* uint256 debtShares */,
            uint256 borrowedSecondaryfCashAmount
        ) = SecondaryBorrowUtils._getDebtSharesToRepay(
            strategyContext.secondaryBorrowCurrencyId, account, maturity, strategyTokenAmount
        );

        // Do not discount secondary fCash amount to present value so that we do not introduce
        // interest rate risk in this calculation. fCash is always in 8 decimal precision, the
        // oraclePairPrice is always in 18 decimal precision and we want our result denominated
        // in the primary token precision.
        // primaryTokenValue = (fCash * rateDecimals * primaryDecimals) / (rate * 1e8)
        uint256 primaryPrecision = 10**poolContext.primaryDecimals;

        uint256 secondaryBorrowedDenominatedInPrimary = (borrowedSecondaryfCashAmount *
                BalancerUtils.BALANCER_PRECISION *
                primaryPrecision) /
                (oraclePairPrice * uint256(Constants.INTERNAL_TOKEN_PRECISION));

        return
            primaryBalance.toInt() -
            secondaryBorrowedDenominatedInPrimary.toInt();
    }
}
