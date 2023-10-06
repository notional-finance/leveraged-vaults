// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    StrategyContext, 
    StrategyVaultSettings, 
    TradeParams,
    ComposablePoolContext
} from "../common/VaultTypes.sol";
import {IStrategyVault} from "../../../interfaces/notional/IStrategyVault.sol";
import {VaultConfig} from "../../../interfaces/notional/IVaultController.sol";
import {IAuraBooster} from "../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../interfaces/aura/IAuraRewardPool.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerVault} from "../../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../../interfaces/balancer/IBalancerMinter.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {IAsset} from "../../../interfaces/balancer/IBalancerVault.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    bytes32 balancerPoolId;
    ILiquidityGauge liquidityGauge;
    ITradingModule tradingModule;
}

struct AuraVaultDeploymentParams {
    IAuraRewardPool rewardPool;
    DeploymentParams baseParams;
}

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

/// @notice Parameters for joining/exiting Balancer pools
struct PoolParams {
    IAsset[] assets;
    uint256[] amounts;
    uint256 msgValue;
    bytes customData;
}

struct ComposableOracleContext {
    /// @notice Amplification parameter
    uint256 ampParam;
    /// @notice Virtual supply
    uint256 virtualSupply;
}

struct AuraStakingContext {
    ILiquidityGauge liquidityGauge;
    address booster;
    IAuraRewardPool rewardPool;
    uint256 poolId;
}

struct BalancerComposablePoolContext {
    ComposablePoolContext basePool;
    uint256[] scalingFactors;
    bytes32 poolId;
    uint8 bptIndex;
}

struct BalancerComposableAuraStrategyContext {
    BalancerComposablePoolContext poolContext;
    ComposableOracleContext oracleContext;
    AuraStakingContext stakingContext;
    StrategyContext baseStrategy;
}