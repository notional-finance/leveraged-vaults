// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {ICurveGauge} from "../../../interfaces/curve/ICurveGauge.sol";
import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";
import {IConvexRewardPool} from "../../../interfaces/convex/IConvexRewardPool.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    address pool;
    ITradingModule tradingModule;
    uint32 settlementPeriodInSeconds;
}

struct ConvexVaultDeploymentParams {
    IConvexRewardPool cvxRewardPool;
    DeploymentParams baseParams;
}

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

/// @notice Curve pool related fields
struct PoolContext {
    ICurvePool pool;
    IERC20 poolToken;
}

struct TwoTokenPoolContext {
    address primaryToken;
    address secondaryToken;
    uint8 primaryIndex;
    uint8 secondaryIndex;
    uint8 primaryDecimals;
    uint8 secondaryDecimals;
    uint256 primaryBalance;
    uint256 secondaryBalance;
    PoolContext basePool;
}

struct ConvexStakingContext {
    IConvexBooster cvxBooster;
    IConvexRewardPool cvxRewardPool;
    uint256 cvxPoolId;
    IERC20[] rewardTokens;
}

struct StrategyVaultSettings {
    /// @notice Cool down in minutes for normal settlement
    uint16 settlementCoolDownInMinutes;
}

struct StrategyVaultState {
    uint256 totalPoolClaim;
    uint256 totalStrategyTokenGlobal;
}

struct StrategyContext {
    uint32 settlementPeriodInSeconds;
    ITradingModule tradingModule;
    StrategyVaultSettings vaultSettings;
    StrategyVaultState vaultState;
}

struct Curve2TokenConvexStrategyContext {
    StrategyContext baseStrategy;
    TwoTokenPoolContext poolContext;
}
