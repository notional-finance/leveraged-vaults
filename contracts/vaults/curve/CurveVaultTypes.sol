// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyContext, StrategyVaultSettings, TradeParams} from "../common/VaultTypes.sol";
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

struct DepositParams {
    uint256 minPoolClaim;
    bytes tradeData;
}

struct TwoTokenRedeemParams {
    uint256 minPrimary;
    uint256 minSecondary;
    bool redeemSingleSided;
    bytes secondaryTradeParams;
}

/// @notice Curve pool related fields
struct PoolContext {
    ICurvePool pool;
    IERC20 poolToken;
}

struct ReinvestRewardParams {
    bytes tradeData;
    uint256 minPoolClaim;
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

struct Curve2TokenConvexStrategyContext {
    StrategyContext baseStrategy;
    TwoTokenPoolContext poolContext;
    ConvexStakingContext stakingContext;
}
