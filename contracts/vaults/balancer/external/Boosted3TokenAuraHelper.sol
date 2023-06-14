// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    Boosted3TokenAuraStrategyContext, 
    Balancer3TokenPoolContext,
    StrategyContext,
    AuraStakingContext,
    BoostedOracleContext
} from "../BalancerVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultSettings,
    StrategyVaultState,
    ThreeTokenPoolContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams
} from "../../common/VaultTypes.sol";
import {VaultConstants} from "../../common/VaultConstants.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {VaultEvents} from "../../common/VaultEvents.sol";
import {SettlementUtils} from "../../common/internal/settlement/SettlementUtils.sol";
import {StrategyUtils} from "../../common/internal/strategy/StrategyUtils.sol";
import {Balancer3TokenBoostedPoolUtils} from "../internal/pool/Balancer3TokenBoostedPoolUtils.sol";
import {Boosted3TokenAuraRewardUtils} from "../internal/reward/Boosted3TokenAuraRewardUtils.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {StableMath} from "../internal/math/StableMath.sol";

library Boosted3TokenAuraHelper {
    using Boosted3TokenAuraRewardUtils for Balancer3TokenPoolContext;
    using Boosted3TokenAuraRewardUtils for ThreeTokenPoolContext;
    using Balancer3TokenBoostedPoolUtils for Balancer3TokenPoolContext;
    using Balancer3TokenBoostedPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultStorage for StrategyVaultSettings;
    using VaultStorage for StrategyVaultState;

    function deposit(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 deposit,
        bytes calldata data
    ) external returns (uint256 vaultSharesMinted) {
        // Entering the vault is not allowed within the settlement window
        DepositParams memory params = abi.decode(data, (DepositParams));

        vaultSharesMinted = context.poolContext._deposit({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            oracleContext: context.oracleContext, 
            deposit: deposit,
            minBPT: params.minPoolClaim
        });
    }

    function redeem(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 vaultShares,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        finalPrimaryBalance = context.poolContext._redeem({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            strategyTokens: vaultShares,
            minPrimary: params.minPrimary
        });
    }

    function settleVaultEmergency(
        Boosted3TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.baseStrategy.vaultSettings.emergencySettlementSlippageLimitPercent,
            data
        );

        uint256 bptToSettle = context.baseStrategy._getEmergencySettlementParams({
            maturity: maturity, 
            totalPoolSupply: context.oracleContext.virtualSupply
        });
        
        // Calculate minPrimary using Chainlink oracle data
        uint256 minPrimary = context.poolContext._getTimeWeightedPrimaryBalance(
            context.oracleContext, context.baseStrategy, bptToSettle
        );

        minPrimary = minPrimary * context.baseStrategy.vaultSettings.poolSlippageLimitPercent / 
            uint256(VaultConstants.VAULT_PERCENT_BASIS);

        context.poolContext._unstakeAndExitPool({
            stakingContext: context.stakingContext,
            bptClaim: bptToSettle,
            minPrimary: minPrimary
        });

        context.baseStrategy.vaultState.totalPoolClaim -= bptToSettle;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        emit VaultEvents.EmergencyVaultSettlement(maturity, bptToSettle, 0);
    }

    function reinvestReward(
        Boosted3TokenAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external returns (
        address rewardToken,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 poolClaimAmount
    ) {
        StrategyContext memory strategyContext = context.baseStrategy;
        BoostedOracleContext calldata oracleContext = context.oracleContext;
        AuraStakingContext calldata stakingContext = context.stakingContext;
        Balancer3TokenPoolContext calldata poolContext = context.poolContext;

        (rewardToken, primaryAmount) = context.poolContext.basePool._executeRewardTrades({
            strategyContext: strategyContext,
            rewardTokens: stakingContext.rewardTokens,
            data: params.tradeData
        });

        /// @notice This function is used to validate the spot price against
        /// the oracle price. The return values are not used.
        poolContext._getValidatedPoolData(oracleContext, strategyContext);

        poolClaimAmount = context.poolContext._joinPoolAndStake({
            strategyContext: strategyContext,
            stakingContext: stakingContext,
            oracleContext: oracleContext,
            deposit: primaryAmount,
            /// @notice Setting minBPT to 0 based on the following assumptions
            /// 1. _getValidatedPoolData already validates the spot price to make sure
            /// the pool isn't being manipulated
            /// 2. We check maxPoolShare before joining to make sure the pool
            /// has adequate liquidity
            /// 3. Manipulating the pool before calling reinvestReward isn't expected
            /// to be very profitable for the attacker because the function gets called
            /// very frequently (relatively small trades)
            minBPT: 0
        });

        strategyContext.vaultState.totalPoolClaim += poolClaimAmount;
        strategyContext.vaultState.setStrategyVaultState(); 

        emit VaultEvents.RewardReinvested(rewardToken, primaryAmount, secondaryAmount, poolClaimAmount); 
    }

    function convertStrategyToUnderlying(
        Boosted3TokenAuraStrategyContext memory context,
        uint256 strategyTokenAmount
    ) external view returns (int256 underlyingValue) {
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            strategyTokenAmount: strategyTokenAmount
        });
    }

    function getSpotPrice(
        Boosted3TokenAuraStrategyContext memory context,
        uint8 tokenIndex
    ) external view returns (uint256 spotPrice) {
        spotPrice = context.poolContext._getSpotPrice(context.oracleContext, tokenIndex);
    }
}
