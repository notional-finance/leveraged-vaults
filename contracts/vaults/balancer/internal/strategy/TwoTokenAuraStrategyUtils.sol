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
    OracleContext,
    SettlementState
} from "../../BalancerVaultTypes.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {Constants} from "../../../../global/Constants.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {TradeHandler} from "../../../../trading/TradeHandler.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {SettlementUtils} from "../settlement/SettlementUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {TwoTokenPoolUtils} from "../pool/TwoTokenPoolUtils.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {SecondaryBorrowUtils} from "../SecondaryBorrowUtils.sol";
import {ITradingModule, Trade} from "../../../../../interfaces/trading/ITradingModule.sol";

library TwoTokenAuraStrategyUtils {
    using TradeHandler for Trade;
    using SafeInt256 for uint256;
    using StrategyUtils for StrategyContext;
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

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(
            bptMinted, NotionalUtils._totalSupplyInMaturity(maturity)
        );
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
        // This check is only necessary during settlement
        if (account != address(this)) {
            poolContext._validateMinExitAmounts({
                oracleContext: oracleContext,
                tradingModule: strategyContext.tradingModule,
                minPrimary: params.minPrimary,
                minSecondary: params.minSecondary
            });
        }

        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(
            strategyTokens, NotionalUtils._totalSupplyInMaturity(maturity)
        );

        if (bptClaim == 0) return 0;

        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance)
            = TwoTokenAuraStrategyUtils._unstakeAndExitPoolExactBPTIn(
                stakingContext, poolContext, bptClaim, params.minPrimary, params.minSecondary
            );

        if (strategyContext.secondaryBorrowCurrencyId != 0) {
            // Returns the amount of secondary debt shares that need to be repaid
            (uint256 debtSharesToRepay, /*  */) = SecondaryBorrowUtils._getAccountDebtSharesToRepay({
                secondaryBorrowCurrencyId: strategyContext.secondaryBorrowCurrencyId, 
                account: account, 
                maturity: maturity, 
                strategyTokenAmount: strategyTokens
            });

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
            uint256 primaryPurchased = SecondaryBorrowUtils._sellSecondaryBalance({
                params: tradeParams,
                tradingModule: strategyContext.tradingModule,
                primaryToken: poolContext.primaryToken,
                secondaryToken: poolContext.secondaryToken,
                secondaryBalance: secondaryBalance
            });

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
            poolContext: poolContext.basePool,
            poolParams: poolParams,
            totalBPTHeld: strategyContext.totalBPTHeld,
            bptThreshold: strategyContext.vaultSettings._bptThreshold(
                poolContext.basePool.pool.totalSupply()
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
            poolContext: poolContext.basePool,
            poolParams: poolContext._getPoolParams(minPrimary, minSecondary, false), // isJoin = false
            bptExitAmount: bptClaim
        });

        (primaryBalance, secondaryBalance) 
            = (exitBalances[poolContext.primaryIndex], exitBalances[poolContext.secondaryIndex]);
    }

    function _convertStrategyToUnderlying(
        StrategyContext memory strategyContext,
        OracleContext memory oracleContext,
        TwoTokenPoolContext memory poolContext,
        uint256 strategyTokenAmount,
        uint256 totalSupplyInMaturity,
        uint256 borrowedSecondaryfCashAmount
    ) internal view returns (int256 underlyingValue) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(
            strategyTokenAmount, totalSupplyInMaturity
        );

        uint256 primaryBalance = poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, bptClaim
        );

        if (strategyContext.secondaryBorrowCurrencyId == 0) return primaryBalance.toInt();

        // Oracle price for the pair in 18 decimals
        uint256 oraclePairPrice = poolContext._getOraclePairPrice(
            oracleContext, strategyContext.tradingModule
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
