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
import {IBalancerVault} from "../../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../../interfaces/balancer/IBalancerMinter.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {IAsset} from "../../../interfaces/balancer/IBalancerVault.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

/// @notice Deployment parameters
struct DeploymentParams {
    /// @notice primary currency id
    uint16 primaryBorrowCurrencyId;
    /// @notice balancer pool ID
    bytes32 balancerPoolId;
    /// @notice trading module proxy
    ITradingModule tradingModule;
}

/// @notice Deployment parameters with Aura staking
struct AuraVaultDeploymentParams {
    /// @notice Aura reward pool address
    IAuraRewardPool rewardPool;
    /// @notice Base deployment parameters
    DeploymentParams baseParams;
}

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

/// @notice Parameters for joining/exiting Balancer pools
struct PoolParams {
    /// @notice asset addresses
    IAsset[] assets;
    /// @notice join/exit amounts
    uint256[] amounts;
    /// @notice amount of ETH to forward
    uint256 msgValue;
    /// @notice custom Balancer join/exit data
    bytes customData;
}

/// @notice Composable pool oracle info
struct ComposableOracleContext {
    /// @notice Amplification parameter
    uint256 ampParam;
    /// @notice Virtual supply
    uint256 virtualSupply;
}

/// @notice Aura staking info
struct AuraStakingContext {
    /// @notice Aura booster address
    address booster;
    /// @notice Aura reward pool address
    IAuraRewardPool rewardPool;
    /// @notice Aura pool ID
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