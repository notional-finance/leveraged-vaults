// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StrategyContext,
    AuraStakingContext,
    TwoTokenPoolContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {TwoTokenAuraStrategyUtils} from "../vaults/balancer/internal/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/TwoTokenPoolUtils.sol";
import {BalancerUtils} from "../vaults/balancer/internal/BalancerUtils.sol";

contract MockTwoTokenAuraStrategyUtils {
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;

    constructor(TwoTokenPoolContext memory poolContext, AuraStakingContext memory stakingContext) {
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function joinPoolAndStake(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        TwoTokenPoolContext memory poolContext,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 minBPT
    ) external returns (uint256 bptMinted) {
        return strategyContext._joinPoolAndStake(
            stakingContext, poolContext, primaryAmount, secondaryAmount, minBPT
        );
    }
}
