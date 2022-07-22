// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolParams,
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyContext
} from "../BalancerVaultTypes.sol";
import {AuraStakingUtils} from "./AuraStakingUtils.sol";
import {VaultUtils} from "./VaultUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";

library TwoTokenAuraStrategyUtils {
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;

    function _joinPoolAndStake(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 minBPT
    ) internal returns (uint256 bptMinted) {
        // prettier-ignore
        PoolParams memory poolParams = poolContext._getPoolParams( 
            primaryAmount, 
            secondaryAmount,
            true // isJoin
        );

        // Join the balancer pool and stake the tokens for boosting
        bptMinted = stakingContext._joinPoolAndStake({
            poolContext: poolContext.baseContext,
            poolParams: poolParams,
            totalBPTHeld: strategyContext.totalBPTHeld,
            bptThreshold: VaultUtils._bptThreshold(
                strategyContext.vaultSettings, 
                poolContext.baseContext.pool.totalSupply()
            ),
            minBPT: minBPT
        });
    }
}
