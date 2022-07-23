// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    DepositParams,
    RedeemParams,
    StrategyContext,
    StableOracleContext,
    TwoTokenPoolContext,
    StrategyVaultState,
    SecondaryTradeParams
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenPoolUtils} from "../internal/TwoTokenPoolUtils.sol";
import {Stable2TokenOracleMath} from "../internal/Stable2TokenOracleMath.sol";
import {SecondaryBorrowUtils} from "../internal/SecondaryBorrowUtils.sol";

library MetaStable2TokenAuraVaultHelper {
    using VaultUtils for StrategyVaultState;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using Stable2TokenOracleMath for StableOracleContext;

    function _depositFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));
        StrategyContext memory strategyContext = context.baseContext;

        // First borrow any secondary tokens (if required)
        uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            context, account, maturity, deposit, params
        );

        uint256 bptMinted = strategyContext._joinPoolAndStake({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            primaryAmount: deposit,
            secondaryAmount: borrowedSecondaryAmount,
            minBPT: params.minBPT
        });

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(bptMinted, maturity);
        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        context.baseContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        VaultUtils._setStrategyVaultState(context.baseContext.vaultState); 
    }

    function _borrowSecondaryCurrency(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 maturity,
        uint256 primaryAmount,
        DepositParams memory params
    ) private returns (uint256) {
        // If secondary currency is not specified then return
        if (context.baseContext.secondaryBorrowCurrencyId == 0) return 0;

        uint256 optimalSecondaryAmount = context.oracleContext._getOptimalSecondaryBorrowAmount(
            context.poolContext, primaryAmount
        );

        return SecondaryBorrowUtils._borrowSecondaryCurrency(
            account, maturity, optimalSecondaryAmount, params
        );
    }

    function _redeemFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        StrategyContext memory strategyContext = context.baseContext;
        TwoTokenPoolContext memory poolContext = context.poolContext;
        // These min primary and min secondary amounts must be within some configured
        // delta of the current oracle price
        poolContext._validateMinExitAmounts({
            oracleContext: context.oracleContext.baseContext,
            tradingModule: context.baseContext.tradingModule,
            minPrimary: params.minPrimary,
            minSecondary: params.minSecondary
        });

        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokens, maturity);

        if (bptClaim == 0) return 0;

        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance)
            = TwoTokenAuraStrategyUtils._unstakeAndExitPoolExactBPTIn(
                context.stakingContext, poolContext, bptClaim, params.minPrimary, params.minSecondary
            );

        if (strategyContext.secondaryBorrowCurrencyId != 0) {
            finalPrimaryBalance = SecondaryBorrowUtils._repaySecondaryBorrow({
                secondaryBorrowCurrencyId: strategyContext.secondaryBorrowCurrencyId,
                account: account,
                maturity: maturity,
                strategyTokens: strategyTokens,
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
}
