// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StrategyContext,
    AuraStakingContext,
    ThreeTokenPoolContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {ThreeTokenAuraStrategyUtils} from "../vaults/balancer/internal/ThreeTokenAuraStrategyUtils.sol";
import {ThreeTokenPoolUtils} from "../vaults/balancer/internal/ThreeTokenPoolUtils.sol";
import {BalancerUtils} from "../vaults/balancer/internal/BalancerUtils.sol";

contract MockThreeTokenAuraStrategyUtils {
    using ThreeTokenPoolUtils for ThreeTokenPoolContext;
    using ThreeTokenAuraStrategyUtils for StrategyContext;

    constructor(ThreeTokenPoolContext memory poolContext, AuraStakingContext memory stakingContext) {
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function joinPoolAndStake(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        uint256 tertiaryAmount,
        uint256 minBPT
    ) external returns (uint256 bptMinted) {
        return strategyContext._joinPoolAndStake(
            stakingContext, poolContext, primaryAmount, secondaryAmount, tertiaryAmount, minBPT
        );
    }

    receive() external payable {}
}
