// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StrategyContext,
    AuraStakingContext,
    ThreeTokenPoolContext,
    BoostedOracleContext,
    Boosted3TokenAuraStrategyContext,
    StrategyVaultState,
    StrategyVaultSettings
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Boosted3TokenPoolUtils} from "../vaults/balancer/internal/pool/Boosted3TokenPoolUtils.sol";
import {BalancerUtils} from "../vaults/balancer/internal/pool/BalancerUtils.sol";
import {StrategyUtils} from "../vaults/balancer/internal/strategy/StrategyUtils.sol";
import {BalancerVaultStorage} from "../vaults/balancer/internal/BalancerVaultStorage.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";

contract MockBoosted3TokenAuraVault {
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using BalancerVaultStorage for StrategyVaultSettings;

    ThreeTokenPoolContext private poolContext;
    BoostedOracleContext private oracleContext;
    AuraStakingContext private stakingContext;
    ITradingModule private tradingModule;
    uint32 private settlementPeriodInSeconds;
    address private feeReceiver;

    constructor(Boosted3TokenAuraStrategyContext memory context) {
        poolContext = context.poolContext;
        oracleContext = context.oracleContext;
        stakingContext = context.stakingContext;
        tradingModule = context.baseStrategy.tradingModule;
        feeReceiver = context.baseStrategy.feeReceiver;
        settlementPeriodInSeconds = context.baseStrategy.settlementPeriodInSeconds;
        context.baseStrategy.vaultSettings.setStrategyVaultSettings(
            context.baseStrategy.vaultSettings.oracleWindowInSeconds,
            context.baseStrategy.vaultSettings.balancerOracleWeight
        );
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function _deposit(uint256 deposit, uint256 maturity, uint256 minBPT) 
        external returns (uint256 bptMinted) {
        return poolContext._deposit(
            _baseStrategyContext(), stakingContext, deposit, minBPT
        );
    }

    function _redeem(uint256 strategyTokens, uint256 maturity, uint256 minPrimary) 
        external returns (uint256 finalPrimaryBalance) {
        return poolContext._redeem(
            _baseStrategyContext(), stakingContext, strategyTokens, minPrimary
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

    function getStrategyContext() public view returns (Boosted3TokenAuraStrategyContext memory) {
        return Boosted3TokenAuraStrategyContext({
            poolContext: poolContext,
            oracleContext: oracleContext,
            stakingContext: stakingContext,
            baseStrategy: _baseStrategyContext()
        });
    }

    function convertStrategyToUnderlying(
        address account, 
        uint256 strategyTokenAmount, 
        uint256 maturity
    ) public view returns (int256 underlyingValue) {
        Boosted3TokenAuraStrategyContext memory context = getStrategyContext();
        underlyingValue = poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            strategyTokenAmount: strategyTokenAmount
        });
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return stakingContext.auraRewardPool.balanceOf(address(this));
    }

    receive() external payable {}
}
