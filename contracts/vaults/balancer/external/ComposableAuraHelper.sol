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
import {Constants} from "../../../global/Constants.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {BalancerComposablePoolUtils} from "../internal/pool/BalancerComposablePoolUtils.sol";
import {ComposableAuraRewardUtils} from "../internal/reward/ComposableAuraRewardUtils.sol";
import {ComposableOracleMath} from "../internal/math/ComposableOracleMath.sol";

library ComposableAuraHelper {
    using BalancerComposablePoolUtils for BalancerComposablePoolContext;
    using ComposableAuraRewardUtils for BalancerComposablePoolContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;
    using TypeConvert for uint256;

    /// @notice Deposits underlying tokens into Balancer and mint strategy tokens
    /// @param context composable pool strategy context
    /// @param deposit token deposit amount
    /// @param data custom deposit data
    /// @return vaultSharesMinted amount of vault shares minted
    function deposit(
        BalancerComposableAuraStrategyContext memory context,
        uint256 deposit,
        bytes calldata data
    ) external returns (uint256 vaultSharesMinted) {
        ComposableDepositParams memory params = abi.decode(data, (ComposableDepositParams));

        vaultSharesMinted = context.poolContext._deposit({
            oracleContext: context.oracleContext,
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            deposit: deposit,
            params: params
        });
    }

    /// @notice Redeem LP tokens from Balancer
    /// @param context composable pool strategy context
    /// @param vaultShares amount of vault shares to redeem
    /// @param data custom redeem data
    /// @return finalPrimaryBalance total amount of underlying tokens redeemed
    function redeem(
        BalancerComposableAuraStrategyContext memory context,
        uint256 vaultShares,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        ComposableRedeemParams memory params = abi.decode(data, (ComposableRedeemParams));

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            vaultShares: vaultShares,
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

    /// @notice Remove liquidity from Balancer in the event of an emergency (i.e. pool gets hacked)
    /// @param context composable pool strategy context
    /// @param data custom redeem data
    function emergencyExit(
        BalancerComposableAuraStrategyContext memory context, 
        bytes calldata data
    ) external {
        // Validate slippage parameter
        ComposableRedeemParams memory params = _decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );
        
        uint256 poolClaimToSettle = context.baseStrategy.vaultState.totalPoolClaim;

        // Min amounts are set to 0 here because we want to be sure that the liquidity can
        // be withdrawn in the event of an emergency where the spot price differs significantly
        // from the oracle price.
        uint256[] memory minAmounts = new uint256[](context.poolContext.basePool.tokens.length);
        
        // Unstake and remove from pool
        context.poolContext._unstakeAndExitPool(
            context.stakingContext, poolClaimToSettle, minAmounts, false
        );

        context.baseStrategy.vaultState.totalPoolClaim = 0;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        emit VaultEvents.EmergencyExit(poolClaimToSettle);
    }

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
            rewardToken, 
            amountSold,
            amounts
        ) = poolContext._executeRewardTrades({
            strategyContext: strategyContext,
            stakingContext: stakingContext,
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
    /// @param tokenIndex pool token index, BPT index is not allowed
    function getSpotPrice(
        BalancerComposableAuraStrategyContext memory context,
        uint8 tokenIndex
    ) external view returns (uint256 spotPrice) {
        spotPrice = ComposableOracleMath._getSpotPrice(
            context.oracleContext, 
            context.poolContext,
            context.poolContext.basePool.primaryIndex,
            tokenIndex
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
