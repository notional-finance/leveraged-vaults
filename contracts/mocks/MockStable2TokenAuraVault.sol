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
import {TwoTokenAuraStrategyUtils} from "../vaults/balancer/internal/TwoTokenAuraStrategyUtils.sol";
import {Stable2TokenOracleMath} from "../vaults/balancer/internal/Stable2TokenOracleMath.sol";
import {VaultUtils} from "../vaults/balancer/internal/VaultUtils.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/TwoTokenPoolUtils.sol";
import {MockTwoTokenVaultBase} from "./MockTwoTokenVaultBase.sol";

contract MockStable2TokenAuraVault is MockTwoTokenVaultBase {
    using Stable2TokenOracleMath for StableOracleContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using VaultUtils for StrategyVaultSettings;

    StableOracleContext private oracleContext;
    AuraStakingContext private stakingContext;
    ITradingModule private tradingModule;
    uint16 private secondaryBorrowCurrencyId;

    constructor(MetaStable2TokenAuraStrategyContext memory context) 
        MockTwoTokenVaultBase(context.poolContext, context.oracleContext.baseOracle) {
        oracleContext = context.oracleContext;
        stakingContext = context.stakingContext;
        secondaryBorrowCurrencyId = context.baseStrategy.secondaryBorrowCurrencyId;
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

    function getStrategyContext() public view returns (MetaStable2TokenAuraStrategyContext memory) {
        return MetaStable2TokenAuraStrategyContext({
            poolContext: poolContext,
            oracleContext: oracleContext,
            stakingContext: stakingContext,
            baseStrategy: StrategyContext({
                totalBPTHeld: _bptHeld(),
                secondaryBorrowCurrencyId: secondaryBorrowCurrencyId,
                tradingModule: tradingModule,
                vaultSettings: VaultUtils._getStrategyVaultSettings(),
                vaultState: VaultUtils._getStrategyVaultState()
            })
        });        
    }
    
    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        return oracleContext._getSpotPrice(poolContext, tokenIndex);
    }

    function getOptimalSecondaryBorrowAmount(uint256 primaryAmount) external view returns (uint256) {
        return oracleContext._getOptimalSecondaryBorrowAmount(poolContext, primaryAmount);
    }  

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return stakingContext.auraRewardPool.balanceOf(address(this));
    }

    receive() external payable {}
}
