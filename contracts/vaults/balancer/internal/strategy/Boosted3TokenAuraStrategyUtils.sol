// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    StrategyContext, 
    ThreeTokenPoolContext, 
    BoostedOracleContext,
    AuraStakingContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {Errors} from "../../../../global/Errors.sol";
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
    using BalancerVaultStorage for StrategyVaultSettings;
    using BalancerVaultStorage for StrategyVaultState;

    function _deposit(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 deposit,
        uint256 minBPT
    ) internal returns (uint256 strategyTokensMinted) {
        uint256 bptMinted = strategyContext._joinPoolAndStake({
            stakingContext: stakingContext,
            poolContext: poolContext,
            deposit: deposit,
            minBPT: minBPT
        });

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

        finalPrimaryBalance = _unstakeAndExitPoolExactBPTIn({
            stakingContext: stakingContext,
            poolContext: poolContext,
            bptClaim: bptClaim,
            minPrimary: minPrimary
        });

        strategyContext.vaultState.totalStrategyTokenGlobal -= strategyTokens.toUint80();
        strategyContext.vaultState.setStrategyVaultState(); 
    }

    function _joinPoolAndStake(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 deposit,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        bptMinted = poolContext._joinPoolExactTokensIn(deposit, minBPT);

        // Check BPT threshold to make sure our share of the pool is
        // below maxBalancerPoolShare
        uint256 bptThreshold = strategyContext.vaultSettings._bptThreshold(
            poolContext.basePool.basePool.pool.totalSupply()
        );
        uint256 bptHeldAfterJoin = strategyContext.totalBPTHeld + bptMinted;
        if (bptHeldAfterJoin > bptThreshold)
            revert Errors.BalancerPoolShareTooHigh(bptHeldAfterJoin, bptThreshold);

        // Transfer token to Aura protocol for boosted staking
        stakingContext.auraBooster.deposit(stakingContext.auraPoolId, bptMinted, true); // stake = true
    }

    function _unstakeAndExitPoolExactBPTIn(
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 bptClaim,
        uint256 minPrimary
    ) internal returns (uint256 primaryBalance) {
        // Withdraw BPT tokens back to the vault for redemption
        stakingContext.auraRewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false

        primaryBalance = poolContext._exitPoolExactBPTIn(bptClaim, minPrimary);    
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
