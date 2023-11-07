// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    StrategyContext,
    StrategyVaultState,
    DepositParams,
    RedeemParams,
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
import {Constants} from "../../../global/Constants.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {BalancerComposablePoolUtils} from "../internal/pool/BalancerComposablePoolUtils.sol";
import {ComposableAuraRewardUtils} from "../internal/reward/ComposableAuraRewardUtils.sol";
import {ComposableOracleMath} from "../internal/math/ComposableOracleMath.sol";
import {
    ReinvestRewardParams
} from "../../../../interfaces/notional/ISingleSidedLPStrategyVault.sol";

library ComposableAuraHelper {
    using BalancerComposablePoolUtils for BalancerComposablePoolContext;
    using ComposableAuraRewardUtils for BalancerComposablePoolContext;
    using VaultStorage for StrategyVaultState;
    using TypeConvert for uint256;

    /// @notice Reinvests the reward tokens
    /// @param context composable pool strategy context
    /// @param params reward reinvestment params
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
        AuraStakingContext calldata stakingContext = context.stakingContext;

        uint256[] memory amounts;
        (
            rewardToken, amountSold, amounts
        ) = poolContext._executeRewardTrades(
            strategyContext, stakingContext, params.tradeData
        );

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

        // Increase LP token amount without minting additional vault shares
        strategyContext.vaultState.totalPoolClaim += poolClaimAmount;
        strategyContext.vaultState.setStrategyVaultState(); 

        emit VaultEvents.RewardReinvested(rewardToken, amountSold, poolClaimAmount); 
    }

    /// @notice Values strategy vault shares in terms of the underlying (primary token)
    /// @param context composable pool strategy context
    /// @param vaultShareAmount amount of vault shares to value
    function convertStrategyToUnderlying(
        BalancerComposableAuraStrategyContext memory context,
        uint256 vaultShareAmount
    ) external view returns (int256 underlyingValue) {
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            vaultShareAmount: vaultShareAmount
        });
    }

    /// @notice Gets the current spot price with a given token index
    /// @notice Spot price is always denominated in the primary token
    /// @param context composable pool strategy context
    /// @param index1 first pool token index, BPT index is not allowed
    /// @param index2 second pool token index, BPT index is not allowed
    function getSpotPrice(
        BalancerComposableAuraStrategyContext memory context,
        uint8 index1,
        uint8 index2
    ) external pure returns (uint256 spotPrice) {
        spotPrice = ComposableOracleMath._getSpotPrice(
            context.oracleContext, 
            context.poolContext,
            index1,
            index2
        );
    }

    /// @notice Gets the exchange rate of a single vault share
    /// @notice The value of 1 BPT is returned if totalVaultSharesGlobal is 0
    /// @param context composable pool strategy context
    function getExchangeRate(BalancerComposableAuraStrategyContext calldata context) external view returns (int256) {
        if (context.baseStrategy.vaultState.totalVaultSharesGlobal == 0) {
            return context.poolContext._getTimeWeightedPrimaryBalance({
                oracleContext: context.oracleContext,
                strategyContext: context.baseStrategy,
                bptAmount: context.baseStrategy.poolClaimPrecision, // 1 pool token
                validateOnly: false
            }).toInt();
        } else {
            return context.poolContext._convertStrategyToUnderlying({
                strategyContext: context.baseStrategy,
                oracleContext: context.oracleContext,
                vaultShareAmount: uint256(Constants.INTERNAL_TOKEN_PRECISION) // 1 vault share
            });
        }
    }
}
