// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {IStrategyVault} from "../../../interfaces/notional/IStrategyVault.sol";
import {VaultConfig} from "../../../interfaces/notional/IVaultController.sol";
import {IBoostController} from "../../../interfaces/notional/IBoostController.sol";
import {IVeBalDelegator} from "../../../interfaces/notional/IVeBalDelegator.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {IBalancerVault} from "../../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../../interfaces/balancer/IBalancerMinter.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";

struct DeploymentParams {
    uint16 secondaryBorrowCurrencyId;
    bytes32 balancerPoolId;
    IBoostController boostController;
    ILiquidityGauge liquidityGauge;
    ITradingModule tradingModule;
    uint32 settlementPeriodInSeconds;
}

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

struct StrategyVaultSettings {
    uint256 maxUnderlyingSurplus;
    /// @notice Balancer oracle window in seconds
    uint32 oracleWindowInSeconds;
    uint16 maxBalancerPoolShare;
    /// @notice Slippage limit for normal settlement
    uint16 settlementSlippageLimit;
    /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
    uint16 postMaturitySettlementSlippageLimit;
    uint16 balancerOracleWeight;
    /// @notice Cool down in minutes for normal settlement
    uint16 settlementCoolDownInMinutes;
    /// @notice Cool down in minutes for post maturity settlement
    uint16 postMaturitySettlementCoolDownInMinutes;
}

struct StrategyVaultState {
    /// @notice Total number of strategy tokens across all maturities
    uint256 totalStrategyTokenGlobal;
    uint32 lastSettlementTimestamp;
    uint32 lastPostMaturitySettlementTimestamp;
}