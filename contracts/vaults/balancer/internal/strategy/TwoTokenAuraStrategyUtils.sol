// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolParams,
    DepositParams,
    DynamicTradeParams,
    DepositTradeParams,
    RedeemParams,
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    OracleContext
} from "../../BalancerVaultTypes.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {Constants} from "../../../../global/Constants.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {TradeHandler} from "../../../../trading/TradeHandler.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {BalancerVaultStorage} from "../BalancerVaultStorage.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {TwoTokenPoolUtils} from "../pool/TwoTokenPoolUtils.sol";
import {Trade} from "../../../../../interfaces/trading/ITradingModule.sol";

library TwoTokenAuraStrategyUtils {
    using TradeHandler for Trade;
    using TokenUtils for IERC20;
    using TypeConvert for uint256;
    using StrategyUtils for StrategyContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using BalancerVaultStorage for StrategyVaultSettings;
    using BalancerVaultStorage for StrategyVaultState;

    /// @notice Trade primary currency for secondary if the trade is specified
    function _tradePrimaryForSecondary(
        StrategyContext memory strategyContext,
        TwoTokenPoolContext memory poolContext,
        bytes memory data
    ) private returns (uint256 primarySold, uint256 secondaryBought) {
        (DepositTradeParams memory params) = abi.decode(data, (DepositTradeParams));

        (primarySold, secondaryBought) = StrategyUtils._executeDynamicTradeExactIn({
            params: params.tradeParams, 
            tradingModule: strategyContext.tradingModule, 
            sellToken: poolContext.primaryToken, 
            buyToken: poolContext.secondaryToken, 
            amount: params.tradeAmount
        });
    }

    function _deposit(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        uint256 deposit,
        DepositParams memory params
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 secondaryAmount;
        if (params.tradeData.length != 0) {
            // Allows users to trade on a different DEX instead of Balancer when joining
            (uint256 primarySold, uint256 secondaryBought) = _tradePrimaryForSecondary({
                strategyContext: strategyContext,
                poolContext: poolContext,
                data: params.tradeData
            });
            deposit -= primarySold;
            secondaryAmount = secondaryBought;
        }

        uint256 bptMinted = strategyContext._joinPoolAndStake({
            stakingContext: stakingContext,
            poolContext: poolContext,
            primaryAmount: deposit,
            secondaryAmount: secondaryAmount,
            minBPT: params.minBPT
        });

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(bptMinted);

        // Update global supply count
        strategyContext.vaultState.totalStrategyTokenGlobal += strategyTokensMinted.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
    }

    function _redeem(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        RedeemParams memory params
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokens);

        if (bptClaim == 0) return 0;

        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance)
            = TwoTokenAuraStrategyUtils._unstakeAndExitPoolExactBPTIn(
                stakingContext, poolContext, bptClaim, params.minPrimary, params.minSecondary
            );
        
        finalPrimaryBalance = primaryBalance;
        if (secondaryBalance > 0) {
            // If there is no secondary debt, we still need to sell the secondary balance
            // back to the primary token here.
            (DynamicTradeParams memory tradeParams) = abi.decode(
                params.secondaryTradeParams, (DynamicTradeParams)
            );
    
            ( /*uint256 amountSold */, uint256 primaryPurchased) = 
                StrategyUtils._executeDynamicTradeExactIn({
                    params: tradeParams,
                    tradingModule: strategyContext.tradingModule,
                    sellToken: poolContext.secondaryToken,
                    buyToken: poolContext.primaryToken,
                    amount: secondaryBalance
                });

            finalPrimaryBalance += primaryPurchased;
        }

        // Update global strategy token balance
        // This only needs to be updated for normal redemption
        // and emergency settlement. For normal and post-maturity settlement
        // scenarios (account == address(this) && data.length == 32), we
        // update totalStrategyTokenGlobal before this function is called.
        strategyContext.vaultState.totalStrategyTokenGlobal -= strategyTokens.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
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
        uint256 strategyTokenAmount
    ) internal view returns (int256 underlyingValue) {
        
        uint256 bptClaim 
            = strategyContext._convertStrategyTokensToBPTClaim(strategyTokenAmount);

        underlyingValue 
            = poolContext._getTimeWeightedPrimaryBalance(oracleContext, bptClaim).toInt();
    }
}
