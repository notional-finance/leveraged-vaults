// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    DepositParams, 
    RedeemParams,
    PoolParams,
    StrategyContext, 
    ThreeTokenPoolContext, 
    AuraStakingContext,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {Boosted3TokenPoolUtils} from "./Boosted3TokenPoolUtils.sol";
import {AuraStakingUtils} from "./AuraStakingUtils.sol";
import {StrategyUtils} from "./StrategyUtils.sol";
import {VaultUtils} from "./VaultUtils.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {IBoostedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";

library Boosted3TokenAuraStrategyUtils {
    using Boosted3TokenAuraStrategyUtils for StrategyContext;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;
    using StrategyUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    function _deposit(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 deposit,
        uint256 maturity,
        uint256 minBPT
    ) internal returns (uint256 strategyTokensMinted) {
        IBoostedPool underlyingPool = IBoostedPool(address(poolContext.basePool.primaryToken));

        // Swap underlyingToken for LinearPool BPT
        uint256 linearPoolBPT = BalancerUtils._swapGivenIn({
            poolId: underlyingPool.getPoolId(),
            tokenIn: underlyingPool.getMainToken(),
            tokenOut: address(underlyingPool),
            amountIn: deposit,
            limit: 0
        });

        // Swap LinearPool BPT for Boosted BPT
        uint256 boostedBPTMinted = BalancerUtils._swapGivenIn({
            poolId: poolContext.basePool.basePool.poolId,
            tokenIn: address(underlyingPool),
            tokenOut: address(poolContext.basePool.basePool.pool), // Boosted pool
            amountIn: linearPoolBPT,
            limit: minBPT
        });

        // Transfer token to Aura protocol for boosted staking
        stakingContext.auraBooster.deposit(stakingContext.auraPoolId, boostedBPTMinted, true); // stake = true

        strategyTokensMinted = strategyContext._convertBPTClaimToStrategyTokens(boostedBPTMinted, maturity);
        require(strategyTokensMinted <= type(uint80).max); /// @dev strategyTokensMinted overflow

        // Update global supply count
        strategyContext.vaultState.totalStrategyTokenGlobal += uint80(strategyTokensMinted);
        strategyContext.vaultState._setStrategyVaultState(); 
    }

    function _redeem(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 strategyTokens,
        uint256 maturity,
        uint256 minPrimary
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 bptClaim = strategyContext._convertStrategyTokensToBPTClaim(strategyTokens, maturity);

        if (bptClaim == 0) return 0;

        // Withdraw BPT tokens back to the vault for redemption
        stakingContext.auraRewardPool.withdrawAndUnwrap(bptClaim, false); // claimRewards = false

        IBoostedPool underlyingPool = IBoostedPool(address(poolContext.basePool.primaryToken));

        // Swap Boosted BPT for LinearPool BPT
        uint256 linearPoolBPT = BalancerUtils._swapGivenIn({
            poolId: poolContext.basePool.basePool.poolId,
            tokenIn: address(poolContext.basePool.basePool.pool), // Boosted pool
            tokenOut: address(underlyingPool),
            amountIn: bptClaim,
            limit: 0
        });

        // Swap LinearPool BPT for underlyingToken
        uint256 primaryBalance = BalancerUtils._swapGivenIn({
            poolId: underlyingPool.getPoolId(),
            tokenIn: address(underlyingPool),
            tokenOut: underlyingPool.getMainToken(),
            amountIn: linearPoolBPT,
            limit: minPrimary
        });

        return primaryBalance;
    }

    function _convertStrategyToUnderlying(
        StrategyContext memory strategyContext,
        ThreeTokenPoolContext memory poolContext,
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) internal view returns (int256 underlyingValue) {
        // TODO: implement this
    }
}
