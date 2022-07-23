// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolParams,
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    OracleContext
} from "../BalancerVaultTypes.sol";
import {SafeInt256} from "../../../global/SafeInt256.sol";
import {AuraStakingUtils} from "./AuraStakingUtils.sol";
import {VaultUtils} from "./VaultUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {SecondaryBorrowUtils} from "./SecondaryBorrowUtils.sol";
import {Constants} from "../../../global/Constants.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";

library TwoTokenAuraStrategyUtils {
    using SafeInt256 for uint256;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

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
