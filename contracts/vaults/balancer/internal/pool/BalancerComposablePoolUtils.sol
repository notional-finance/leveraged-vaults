// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    BalancerComposablePoolContext, 
    StableOracleContext, 
    PoolParams,
    AuraStakingContext
} from "../../BalancerVaultTypes.sol";
import {
    TradeParams,
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    ComposablePoolContext,
    DepositParams,
    RedeemParams
} from "../../../common/VaultTypes.sol";
import {Deployments} from "../../../../global/Deployments.sol";
import {IBalancerVault, IAsset} from "../../../../../interfaces/balancer/IBalancerVault.sol";
import {TokenUtils, IERC20} from "../../../../utils/TokenUtils.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";

library BalancerComposablePoolUtils {
    using TokenUtils for IERC20;
    using StrategyUtils for StrategyContext;

    /// @notice Returns parameters for joining and exiting Balancer pools
    /// @param bptAmount minBptAmount if isJoin is true, bptExitAmount if isJoin is false
    function _getPoolParams(
        BalancerComposablePoolContext memory context,
        uint256[] memory amounts,
        bool isJoin,
        bool isSingleSided,
        uint256 bptAmount
    ) internal pure returns (PoolParams memory) {
        IAsset[] memory assets = new IAsset[](context.basePool.tokens.length);

        uint256 msgValue;
        for (uint256 i; i < context.basePool.tokens.length; i++) {
            assets[i] = IAsset(context.basePool.tokens[i]);
            if (isJoin) {
                if (assets[i] == IAsset(Deployments.ETH_ADDRESS)) {
                    msgValue += amounts[i];
                }
            }
        }

        bytes memory customData;
        if (isJoin) {
            customData = abi.encode(
                IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                _getAmountsWithoutBpt(context, amounts),
                bptAmount // Apply minBPT to prevent front running
            );
        } else {
            if (isSingleSided) {
                customData = abi.encode(
                    IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                    bptAmount,
                    context.basePool.primaryIndex
                );
            } else {
                customData = abi.encode(
                    IBalancerVault.ComposableExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT,
                    bptAmount
                );
            }
        }

        return PoolParams(assets, amounts, msgValue, customData);
    }

    function _getAmountsWithoutBpt(BalancerComposablePoolContext memory context, uint256[] memory inAmounts) 
        private pure returns (uint256[] memory amountsWithoutBpt) {
        amountsWithoutBpt = new uint256[](inAmounts.length - 1);
        uint256 j;
        for (uint256 i; i < inAmounts.length; i++) {
            if (i == context.bptIndex) {
                continue;
            }
            amountsWithoutBpt[j++] = inAmounts[i];
        }
    }

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @param poolContext pool context variables
    /// @param oracleContext oracle context variables
    /// @param bptAmount amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function _getTimeWeightedPrimaryBalance(
        BalancerComposablePoolContext memory poolContext,
        StableOracleContext memory oracleContext,
        StrategyContext memory strategyContext,
        uint256 bptAmount
    ) internal view returns (uint256 primaryAmount) {
        /*uint256 oraclePairPrice = poolContext.basePool._getOraclePairPrice(strategyContext);

        // tokenIndex == 0 because _getOraclePairPrice always returns the price in terms of
        // the primary currency
        uint256 spotPrice = oracleContext._getSpotPrice({
            poolContext: poolContext,
            primaryBalance: poolContext.basePool.primaryBalance,
            secondaryBalance: poolContext.basePool.secondaryBalance,
            tokenIndex: 0
        });

        primaryAmount = poolContext.basePool._getTimeWeightedPrimaryBalance({
            strategyContext: strategyContext,
            poolClaim: bptAmount,
            oraclePrice: oraclePairPrice,
            spotPrice: spotPrice
        });*/
    }

    function _approveBalancerTokens(ComposablePoolContext memory poolContext, address bptSpender) internal {
        for (uint256 i; i < poolContext.tokens.length; i++) {
            IERC20(poolContext.tokens[i]).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
        }

        // Allow BPT spender to pull BALANCER_POOL_TOKEN
        poolContext.poolToken.checkApprove(bptSpender, type(uint256).max);
    }

    function _deposit(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256 deposit,
        DepositParams memory params
    ) internal returns (uint256 strategyTokensMinted) {
        uint256[] memory amounts = new uint256[](poolContext.basePool.tokens.length);

       /* if (params.tradeData.length != 0) {
            // Allows users to trade on a different DEX instead of Balancer when joining
            (uint256 primarySold, uint256 secondaryBought) = poolContext.basePool._tradePrimaryForSecondary({
                strategyContext: strategyContext,
                data: params.tradeData
            });
            deposit -= primarySold;
            secondaryAmount = secondaryBought;
        }*/

        amounts[poolContext.basePool.primaryIndex] = deposit;

        uint256 bptMinted = _joinPoolAndStake({
            poolContext: poolContext,
            strategyContext: strategyContext,
            stakingContext: stakingContext,
            amounts: amounts,
            minBPT: params.minPoolClaim
        });

        strategyTokensMinted = strategyContext._mintStrategyTokens(bptMinted);
    }

    function _redeem(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256 strategyTokens,
        RedeemParams memory params
    ) internal returns (uint256 finalPrimaryBalance) {
       /* uint256 bptClaim = strategyContext._redeemStrategyTokens(strategyTokens);
        bool isSingleSidedExit = params.secondaryTradeParams.length == 0;

        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance)
            = _unstakeAndExitPool(
                poolContext, stakingContext, bptClaim, params.minPrimary, params.minSecondary, isSingleSidedExit
            );

        finalPrimaryBalance = primaryBalance;
        if (secondaryBalance > 0) {
            uint256 primaryPurchased = poolContext.basePool._sellSecondaryBalance(
                strategyContext, params, secondaryBalance
            );

            finalPrimaryBalance += primaryPurchased;
        } */
    }

    function _joinPoolAndStake(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        uint256[] memory amounts,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        // prettier-ignore
        PoolParams memory poolParams = _getPoolParams({
            context: poolContext,
            amounts: amounts,
            isJoin: true,
            isSingleSided: false,
            bptAmount: minBPT
        });

        bptMinted = BalancerUtils._joinPoolExactTokensIn({
            poolId: poolContext.poolId,
            poolToken: poolContext.basePool.poolToken,
            params: poolParams
        });

        // Check BPT threshold to make sure our share of the pool is
        // below maxPoolShare
      /*  uint256 bptThreshold = strategyContext.vaultSettings._poolClaimThreshold(
            poolContext.basePool.poolToken.totalSupply()
        );
        uint256 bptHeldAfterJoin = strategyContext.vaultState.totalPoolClaim + bptMinted;
        if (bptHeldAfterJoin > bptThreshold)
            revert Errors.PoolShareTooHigh(bptHeldAfterJoin, bptThreshold);

        // Transfer token to Aura protocol for boosted staking
        bool success = IAuraBoosterBase(stakingContext.booster).deposit(stakingContext.poolId, bptMinted, true); // stake = true
        if (!success) revert Errors.StakeFailed(); */
    }

    function _unstakeAndExitPool(
        BalancerComposablePoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        uint256 bptClaim,
        uint256 minPrimary,
        uint256 minSecondary,
        bool isSingleSidedExit
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
    /*    bool success = stakingContext.rewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false
        if (!success) revert Errors.UnstakeFailed();

        uint256[] memory exitBalances = _exitPool(poolContext, bptClaim, minPrimary, minSecondary, isSingleSidedExit);

        (primaryBalance, secondaryBalance) 
            = (exitBalances[poolContext.basePool.primaryIndex], exitBalances[poolContext.basePool.secondaryIndex]); */
    }

    function _exitPool(
        BalancerComposablePoolContext memory poolContext,
        uint256 bptClaim,
        uint256 minPrimary,
        uint256 minSecondary,
        bool isSingleSidedExit
    ) private returns (uint256[] memory) {
      /*  return BalancerUtils._exitPoolExactBPTIn({
            poolId: poolContext.poolId,
            poolToken: poolContext.basePool.poolToken,
            params: poolContext._getPoolParams({
                primaryAmount: minPrimary,
                secondaryAmount: minSecondary,
                isJoin: false,
                isSingleSidedExit: isSingleSidedExit,
                bptExitAmount: bptClaim
            }),
            bptExitAmount: bptClaim
        }); */
    }

    /// @notice We value strategy tokens in terms of the primary balance. The time weighted
    /// primary balance is used in order to prevent pool manipulation.
    /// @param poolContext pool context variables
    /// @param strategyContext strategy context variables
    /// @param oracleContext oracle context variables
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return underlyingValue underlying value of strategy tokens
    function _convertStrategyToUnderlying(
        BalancerComposablePoolContext memory poolContext,
        StrategyContext memory strategyContext,
        StableOracleContext memory oracleContext,
        uint256 strategyTokenAmount
    ) internal view returns (int256 underlyingValue) {
        
      /*  uint256 bptClaim 
            = strategyContext._convertStrategyTokensToPoolClaim(strategyTokenAmount);

        underlyingValue 
            = poolContext._getTimeWeightedPrimaryBalance(oracleContext, strategyContext, bptClaim).toInt(); */
    }
}
