// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyContext, ComposablePoolContext} from "../common/VaultTypes.sol";
import {IAuraRewardPool} from "../../../interfaces/aura/IAuraRewardPool.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {IAsset} from "../../../interfaces/balancer/IBalancerVault.sol";

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

/// @notice Balancer composable pool context
struct BalancerComposablePoolContext {
    /// @notice base pool context
    ComposablePoolContext basePool;
    /// @notice scaling factors
    uint256[] scalingFactors;
    /// @notice Balancer pool ID
    bytes32 poolId;
    /// @notice BPT index
    uint8 bptIndex;
}

/// @notice Balancer composable with Aura staking strategy context
struct BalancerComposableAuraStrategyContext {
    /// @notice pool context
    BalancerComposablePoolContext poolContext;
    /// @notice oracle context
    ComposableOracleContext oracleContext;
    /// @notice staking context
    AuraStakingContext stakingContext;
    /// @notice base strategy context
    StrategyContext baseStrategy;
}