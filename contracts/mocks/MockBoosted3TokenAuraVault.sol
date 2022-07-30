// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StrategyContext,
    AuraStakingContext,
    ThreeTokenPoolContext,
    Boosted3TokenAuraStrategyContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Boosted3TokenAuraVaultHelper} from "../vaults/balancer/external/Boosted3TokenAuraVaultHelper.sol";
import {Boosted3TokenAuraStrategyUtils} from "../vaults/balancer/internal/Boosted3TokenAuraStrategyUtils.sol";
import {Boosted3TokenPoolUtils} from "../vaults/balancer/internal/Boosted3TokenPoolUtils.sol";
import {BalancerUtils} from "../vaults/balancer/internal/BalancerUtils.sol";

contract MockBoosted3TokenAuraVault {
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;

    constructor(ThreeTokenPoolContext memory poolContext, AuraStakingContext memory stakingContext) {
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function _deposit(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 deposit,
        uint256 maturity,
        uint256 minBPT
    ) external returns (uint256 bptMinted) {
        return strategyContext._deposit(
            stakingContext, poolContext, deposit, maturity, minBPT
        );
    }

    function _redeem(
        StrategyContext memory strategyContext,
        AuraStakingContext memory stakingContext,
        ThreeTokenPoolContext memory poolContext,
        uint256 strategyTokens,
        uint256 maturity,
        uint256 minPrimary
    ) external returns (uint256 finalPrimaryBalance) {
        return strategyContext._redeem(
            stakingContext, poolContext, strategyTokens, maturity, minPrimary
        );
    }

    receive() external payable {}
}
