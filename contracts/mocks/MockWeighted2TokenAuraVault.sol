// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StrategyContext,
    AuraStakingContext,
    TwoTokenPoolContext,
    WeightedOracleContext,
    Weighted2TokenAuraStrategyContext,
    StrategyVaultSettings
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {TwoTokenAuraStrategyUtils} from "../vaults/balancer/internal/strategy/TwoTokenAuraStrategyUtils.sol";
import {VaultUtils} from "../vaults/balancer/internal/VaultUtils.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/pool/TwoTokenPoolUtils.sol";
import {BalancerUtils} from "../vaults/balancer/internal/pool/BalancerUtils.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {Weighted2TokenOracleMath} from "../vaults/balancer/internal/math/Weighted2TokenOracleMath.sol";
import {MockTwoTokenVaultBase} from "./MockTwoTokenVaultBase.sol";

contract MockWeighted2TokenAuraVault is MockTwoTokenVaultBase {
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Weighted2TokenOracleMath for WeightedOracleContext;
    using VaultUtils for StrategyVaultSettings;

    WeightedOracleContext private oracleContext;
    AuraStakingContext private stakingContext;
    ITradingModule private tradingModule;
    uint32 private settlementPeriodInSeconds;

    constructor(Weighted2TokenAuraStrategyContext memory context) 
        MockTwoTokenVaultBase(context.poolContext, context.oracleContext.baseOracle) {
        oracleContext = context.oracleContext;
        stakingContext = context.stakingContext;
        settlementPeriodInSeconds = context.baseStrategy.settlementPeriodInSeconds;
        tradingModule = context.baseStrategy.tradingModule;
        context.baseStrategy.vaultSettings._setStrategyVaultSettings(
            context.baseStrategy.vaultSettings.oracleWindowInSeconds,
            context.baseStrategy.vaultSettings.balancerOracleWeight
        );
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 minBPT) 
        external returns (uint256 bptMinted) {
        return getStrategyContext().baseStrategy._joinPoolAndStake(
            stakingContext, poolContext, primaryAmount, secondaryAmount, minBPT
        );
    }

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256) {
        return oracleContext._getSpotPrice(poolContext, tokenIndex);
    }

    function getStrategyContext() public view returns (Weighted2TokenAuraStrategyContext memory) {
        return Weighted2TokenAuraStrategyContext({
            poolContext: poolContext,
            oracleContext: oracleContext,
            stakingContext: stakingContext,
            baseStrategy: StrategyContext({
                totalBPTHeld: _bptHeld(),
                settlementPeriodInSeconds: settlementPeriodInSeconds,
                tradingModule: tradingModule,
                vaultSettings: VaultUtils._getStrategyVaultSettings(),
                vaultState: VaultUtils._getStrategyVaultState()
            })
        });        
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return stakingContext.auraRewardPool.balanceOf(address(this));
    }

    receive() external payable {}
}
