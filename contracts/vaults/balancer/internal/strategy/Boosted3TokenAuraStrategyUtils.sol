// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    StrategyContext, 
    ThreeTokenPoolContext, 
    BoostedOracleContext,
    AuraStakingContext,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {BalancerVaultStorage} from "../BalancerVaultStorage.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";

// @audit I think it's unlikely that we move away from Aura in the short run, so maybe this
// can be merged into Boosted3TokenPoolUtils instead.
library Boosted3TokenAuraStrategyUtils {
    using TypeConvert for uint256;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using StrategyUtils for StrategyContext;
    using BalancerVaultStorage for StrategyVaultState;

    function _deposit(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 deposit,
        uint256 minBPT
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 bptMinted = poolContext._joinPoolExactTokensIn(deposit, minBPT);

        // Transfer token to Aura protocol for boosted staking
        // @audit can we move this into _exitPoolExactBPTIn?
        stakingContext.auraBooster.deposit(stakingContext.auraPoolId, bptMinted, true); // stake = true

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(bptMinted);

        // Update global supply count
        strategyContext.vaultState.totalStrategyTokenGlobal += strategyTokensMinted.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
    }

    function _redeem(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 strategyTokens,
        uint256 minPrimary
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokens);

        if (bptClaim == 0) return 0;

        // Withdraw BPT tokens back to the vault for redemption
        // @audit can we move this into _exitPoolExactBPTIn?
        stakingContext.auraRewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false

        uint256 primaryBalance = poolContext._exitPoolExactBPTIn(bptClaim, minPrimary);

        strategyContext.vaultState.totalStrategyTokenGlobal -= strategyTokens.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
        
        return primaryBalance;
    }

    // @audit this probably deserves more commentary, also would think this makes
    // more sense inside Boosted3TokenPoolUtils since Aura has nothing to do with the
    // valuation
    function _convertStrategyToUnderlying(
        StrategyContext memory strategyContext,
        BoostedOracleContext memory oracleContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 strategyTokenAmount
    ) internal view returns (int256 underlyingValue) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokenAmount);
        
        underlyingValue = poolContext._getTimeWeightedPrimaryBalance(
            oracleContext, 
            strategyContext.tradingModule, 
            bptClaim
        ).toInt();
    }
}
