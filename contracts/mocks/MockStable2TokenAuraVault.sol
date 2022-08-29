// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    StrategyContext,
    StableOracleContext, 
    OracleContext, 
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyVaultSettings
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Stable2TokenOracleMath} from "../vaults/balancer/internal/math/Stable2TokenOracleMath.sol";
import {BalancerVaultStorage} from "../vaults/balancer/internal/BalancerVaultStorage.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/pool/TwoTokenPoolUtils.sol";
import {MockTwoTokenVaultBase} from "./MockTwoTokenVaultBase.sol";

contract MockStable2TokenAuraVault is MockTwoTokenVaultBase {
    using Stable2TokenOracleMath for StableOracleContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using BalancerVaultStorage for StrategyVaultSettings;

    StableOracleContext private oracleContext;
    AuraStakingContext private stakingContext;
    ITradingModule private tradingModule;
    uint32 private settlementPeriodInSeconds;
    address private feeReceiver;

    constructor(MetaStable2TokenAuraStrategyContext memory context) 
        MockTwoTokenVaultBase(context.poolContext, context.oracleContext.baseOracle) {
        oracleContext = context.oracleContext;
        stakingContext = context.stakingContext;
        settlementPeriodInSeconds = context.baseStrategy.settlementPeriodInSeconds;
        tradingModule = context.baseStrategy.tradingModule;
        feeReceiver = context.baseStrategy.feeReceiver;
        context.baseStrategy.vaultSettings.setStrategyVaultSettings(
            context.baseStrategy.vaultSettings.oracleWindowInSeconds,
            context.baseStrategy.vaultSettings.balancerOracleWeight
        );    
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 minBPT) 
        external returns (uint256 bptMinted) {
        return poolContext._joinPoolAndStake(
            _baseStrategyContext(), stakingContext, primaryAmount, secondaryAmount, minBPT
        );
    }

    function _baseStrategyContext() internal view returns (StrategyContext memory) {
        return StrategyContext({
            totalBPTHeld: _bptHeld(),
            settlementPeriodInSeconds: settlementPeriodInSeconds,
            tradingModule: tradingModule,
            vaultSettings: BalancerVaultStorage.getStrategyVaultSettings(),
            vaultState: BalancerVaultStorage.getStrategyVaultState(),
            feeReceiver: feeReceiver
        });
    }

    function getStrategyContext() public view returns (MetaStable2TokenAuraStrategyContext memory) {
        return MetaStable2TokenAuraStrategyContext({
            poolContext: poolContext,
            oracleContext: oracleContext,
            stakingContext: stakingContext,
            baseStrategy: _baseStrategyContext()
        });        
    }
    
    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        return oracleContext._getSpotPrice(poolContext, tokenIndex);
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return stakingContext.auraRewardPool.balanceOf(address(this));
    }

    receive() external payable {}
}
