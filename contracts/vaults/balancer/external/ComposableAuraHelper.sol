// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    ComposableDepositParams,
    ComposableRedeemParams,
    ReinvestRewardParams
} from "../../common/VaultTypes.sol";
import {
    AuraVaultDeploymentParams,
    BalancerComposablePoolContext,
    BalancerComposableAuraStrategyContext,
    ComposableOracleContext,
    AuraStakingContext
} from "../BalancerVaultTypes.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {BalancerComposablePoolUtils} from "../internal/pool/BalancerComposablePoolUtils.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";

library ComposableAuraHelper {
    using BalancerComposablePoolUtils for BalancerComposablePoolContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;

    function deposit(
        BalancerComposableAuraStrategyContext memory context,
        uint256 deposit,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        ComposableDepositParams memory params = abi.decode(data, (ComposableDepositParams));

        strategyTokensMinted = context.poolContext._deposit({
            oracleContext: context.oracleContext,
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            deposit: deposit,
            params: params
        });
    }

    function redeem(
        BalancerComposableAuraStrategyContext memory context,
        uint256 strategyTokens,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        ComposableRedeemParams memory params = abi.decode(data, (ComposableRedeemParams));

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            strategyTokens: strategyTokens,
            params: params
        });
    }

    function settleVaultEmergency(
        BalancerComposableAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        /*ComposableRedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );
        bool isSingleSidedExit = params.secondaryTradeParams.length == 0;

        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.oracleContext.virtualSupply
        });

        uint256 oraclePrice = context.poolContext.basePool._getOraclePairPrice(context.baseStrategy);

        /// @notice params.minPrimary and params.minSecondary are not required to be passed in by the caller
        /// for this strategy vault
        (uint256 minPrimary, uint256 minSecondary) = context.oracleContext._getMinExitAmounts({
            poolContext: context.poolContext,
            strategyContext: context.baseStrategy,
            oraclePrice: oraclePrice,
            bptAmount: bptToSettle
        });

        context.poolContext._unstakeAndExitPool(
            context.stakingContext, bptToSettle, minPrimary, minSecondary, isSingleSidedExit
        );

        context.baseStrategy.vaultState.totalPoolClaim -= bptToSettle;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        emit VaultEvents.EmergencyVaultSettlement(maturity, bptToSettle, 0); */
    }

    function reinvestReward(
        BalancerComposableAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external returns (
        address rewardToken,
        uint256 amountSold, 
        uint256 poolClaimAmount
    ) {
        StrategyContext memory strategyContext = context.baseStrategy;
        BalancerComposablePoolContext calldata poolContext = context.poolContext; 
        ComposableOracleContext calldata oracleContext = context.oracleContext;

        uint256[] memory amounts;
        (
            rewardToken, 
            amountSold,
            amounts
        ) = poolContext._executeRewardTrades({
            strategyContext: strategyContext,
            rewardTokens: context.stakingContext.rewardTokens,
            data: params.tradeData
        });

        // Make sure we are joining with the right proportion to minimize slippage
        /*oracleContext._validateSpotPriceAndPairPrice({
            poolContext: poolContext,
            strategyContext: strategyContext,
            oraclePrice: poolContext.basePool._getOraclePairPrice(strategyContext),
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });*/

        poolClaimAmount = poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            oracleContext: oracleContext,
            stakingContext: context.stakingContext,
            amounts: amounts,
            /// @notice minBPT is not required to be set by the caller because primaryAmount
            /// and secondaryAmount are already validated
            minBPT: params.minPoolClaim      
        });

        strategyContext.vaultState.totalPoolClaim += poolClaimAmount;
        strategyContext.vaultState.setStrategyVaultState(); 

        emit VaultEvents.RewardReinvested(rewardToken, amountSold, poolClaimAmount); 
    }
}
