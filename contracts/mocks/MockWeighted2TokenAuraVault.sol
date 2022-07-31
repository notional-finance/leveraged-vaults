// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StrategyContext,
    AuraStakingContext,
    TwoTokenPoolContext,
    WeightedOracleContext,
    Weighted2TokenAuraStrategyContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {TwoTokenAuraStrategyUtils} from "../vaults/balancer/internal/TwoTokenAuraStrategyUtils.sol";
import {VaultUtils} from "../vaults/balancer/internal/VaultUtils.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/TwoTokenPoolUtils.sol";
import {BalancerUtils} from "../vaults/balancer/internal/BalancerUtils.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {Weighted2TokenOracleMath} from "../vaults/balancer/internal/Weighted2TokenOracleMath.sol";

contract MockWeighted2TokenAuraVault {
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Weighted2TokenOracleMath for WeightedOracleContext;

    TwoTokenPoolContext poolContext;
    WeightedOracleContext oracleContext;
    AuraStakingContext stakingContext;
    ITradingModule tradingModule;
    uint16 secondaryBorrowCurrencyId;

    constructor(Weighted2TokenAuraStrategyContext memory context) {
        poolContext = context.poolContext;
        oracleContext = context.oracleContext;
        stakingContext = context.stakingContext;
        secondaryBorrowCurrencyId = context.baseStrategy.secondaryBorrowCurrencyId;
        tradingModule = context.baseStrategy.tradingModule;
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256) {
        return oracleContext._getSpotPrice(poolContext, tokenIndex);
    }

    function getOptimalSecondaryBorrowAmount(uint256 primaryAmount) external view returns (uint256) {
        return oracleContext._getOptimalSecondaryBorrowAmount(poolContext, primaryAmount);
    }

    function getStrategyContext() external view returns (Weighted2TokenAuraStrategyContext memory) {
        return Weighted2TokenAuraStrategyContext({
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

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return stakingContext.auraRewardPool.balanceOf(address(this));
    }

    receive() external payable {}
}
