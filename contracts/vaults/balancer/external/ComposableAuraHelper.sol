// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    ComposableDepositParams,
    ComposableRedeemParams,
    ReinvestRewardParams,
    TradeParams
} from "../../common/VaultTypes.sol";
import {
    AuraVaultDeploymentParams,
    BalancerComposablePoolContext,
    BalancerComposableAuraStrategyContext,
    ComposableOracleContext,
    AuraStakingContext
} from "../BalancerVaultTypes.sol";
import {Errors} from "../../../global/Errors.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {SettlementUtils} from "../../common/internal/settlement/SettlementUtils.sol";
import {BalancerComposablePoolUtils} from "../internal/pool/BalancerComposablePoolUtils.sol";
import {ComposableAuraRewardUtils} from "../internal/reward/ComposableAuraRewardUtils.sol";

library ComposableAuraHelper {
    using BalancerComposablePoolUtils for BalancerComposablePoolContext;
    using ComposableAuraRewardUtils for BalancerComposablePoolContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;
    using SettlementUtils for StrategyContext;

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

    /// @notice Validates that the slippage passed in by the caller
    /// does not exceed the designated threshold.
    /// @param slippageLimitPercent configured limit on the slippage from the oracle price allowed
    /// @param data trade parameters passed into settlement
    /// @return params abi decoded redemption parameters
    function _decodeParamsAndValidate(
        uint32 slippageLimitPercent,
        bytes memory data
    ) internal view returns (ComposableRedeemParams memory params) {
        params = abi.decode(data, (ComposableRedeemParams));
        if (params.redemptionTrades.length != 0) {
            for (uint256 i; i < params.redemptionTrades.length; i++) {
                TradeParams memory tradeParams = params.redemptionTrades[i];

                if (slippageLimitPercent < tradeParams.oracleSlippagePercentOrLimit) {
                    revert Errors.SlippageTooHigh(tradeParams.oracleSlippagePercentOrLimit, slippageLimitPercent);
                }
            }
        }
    }

    function settleVaultEmergency(
        BalancerComposableAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        ComposableRedeemParams memory params = _decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );
        bool isSingleSidedExit = params.redemptionTrades.length == 0;
        
        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.oracleContext.virtualSupply
        });

        /// @notice minAmounts are not required to be passed in by the caller for this strategy vault
        uint256[] memory minAmounts = context.poolContext._getMinExitAmounts({
            oracleContext: context.oracleContext,
            strategyContext: context.baseStrategy,
            poolClaim: bptToSettle
        });

        context.poolContext._unstakeAndExitPool(
            context.stakingContext, bptToSettle, minAmounts, isSingleSidedExit
        );

        context.baseStrategy.vaultState.totalPoolClaim -= bptToSettle;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        emit VaultEvents.EmergencyVaultSettlement(maturity, bptToSettle, 0);
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
        poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, strategyContext, 0, true // validateOnly = true
        );

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
