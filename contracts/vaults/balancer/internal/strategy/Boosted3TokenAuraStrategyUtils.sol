// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    StrategyContext, 
    ThreeTokenPoolContext, 
    BoostedOracleContext,
    AuraStakingContext,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";

// @audit I think it's unlikely that we move away from Aura in the short run, so maybe this
// can be merged into Boosted3TokenPoolUtils instead.
library Boosted3TokenAuraStrategyUtils {
    using SafeInt256 for uint256;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using StrategyUtils for StrategyContext;
    using VaultUtils for StrategyVaultState;

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
        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        // @audit Can we calculate this value instead of storing it? That will be less error prone, it would
        // require us looping over all the active vault states.
        strategyContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        strategyContext.vaultState._setStrategyVaultState(); 
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

        // @audit is this comment still correct? there is no if block around this statement
        // Update global strategy token balance
        // This only needs to be updated for normal redemption
        // and emergency settlement. For normal and post-maturity settlement
        // scenarios (account == address(this) && data.length == 32), we
        // update totalStrategyTokenGlobal before this function is called.
        strategyContext.vaultState.totalStrategyTokenGlobal -= uint80(strategyTokens);
        strategyContext.vaultState._setStrategyVaultState(); 
        
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
