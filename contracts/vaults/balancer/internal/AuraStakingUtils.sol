// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {AuraStakingContext, PoolContext, PoolParams} from "../BalancerVaultTypes.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {BalancerUtils} from "../BalancerUtils.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";

library AuraStakingUtils {
    error BalancerPoolShareTooHigh(uint256 totalBPTHeld, uint256 bptThreshold);

    function _joinPoolAndStake(
        AuraStakingContext memory stakingContext,
        PoolContext memory poolContext,
        PoolParams memory poolParams,
        uint256 totalBPTHeld, 
        uint256 bptThreshold,
        uint256 minBPT
    ) internal returns (uint256 bptAmount) {
        bptAmount = BalancerUtils.joinPoolExactTokensIn({
            context: poolContext,
            params: poolParams,
            minBPT: minBPT
        });

        // Check BPT threshold to make sure our share of the pool is
        // below maxBalancerPoolShare
        uint256 bptHeldAfterJoin = totalBPTHeld + bptAmount;
        if (bptHeldAfterJoin > bptThreshold)
            revert BalancerPoolShareTooHigh(bptHeldAfterJoin, bptThreshold);

        // Transfer token to Aura protocol for boosted staking
        stakingContext.auraBooster.deposit(stakingContext.auraPoolId, bptAmount, true); // stake = true
    }

    function _unstakeAndExitPoolExactBPTIn(
        AuraStakingContext memory stakingContext,
        PoolContext memory poolContext,
        PoolParams memory poolParams,
        uint256 bptExitAmount
    ) internal returns (uint256[] memory exitBalances) {
        // Withdraw BPT tokens back to the vault for redemption
        stakingContext.auraRewardPool.withdrawAndUnwrap(bptExitAmount, false); // claimRewards = false

        exitBalances = BalancerUtils._exitPoolExactBPTIn({
            context: poolContext,
            params: poolParams,
            bptExitAmount: bptExitAmount
        });
    }
}
