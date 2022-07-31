// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    StrategyContext,
    StableOracleContext, 
    OracleContext, 
    TwoTokenPoolContext,
    AuraStakingContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Stable2TokenOracleMath} from "../vaults/balancer/internal/Stable2TokenOracleMath.sol";
import {VaultUtils} from "../vaults/balancer/internal/VaultUtils.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/TwoTokenPoolUtils.sol";

contract MockStable2TokenAuraVault {
    using Stable2TokenOracleMath for StableOracleContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    TwoTokenPoolContext poolContext;
    StableOracleContext oracleContext;
    AuraStakingContext stakingContext;
    ITradingModule tradingModule;
    uint16 secondaryBorrowCurrencyId;

    constructor(MetaStable2TokenAuraStrategyContext memory context) {
        poolContext = context.poolContext;
        oracleContext = context.oracleContext;
        stakingContext = context.stakingContext;
        secondaryBorrowCurrencyId = context.baseStrategy.secondaryBorrowCurrencyId;
        tradingModule = context.baseStrategy.tradingModule;
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function getStrategyContext() external view returns (MetaStable2TokenAuraStrategyContext memory) {
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
