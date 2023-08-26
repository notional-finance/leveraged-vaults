// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import {
    StrategyContext, 
    StrategyVaultSettings, 
    TradeParams, 
    TwoTokenPoolContext
} from "../common/VaultTypes.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {ICurveGauge} from "../../../interfaces/curve/ICurveGauge.sol";
import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    address pool;
    ITradingModule tradingModule;
    bool isSelfLPToken;
}

struct ConvexVaultDeploymentParams {
    address rewardPool;
    DeploymentParams baseParams;
}

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

struct Curve2TokenPoolContext {
    TwoTokenPoolContext basePool;
    address curvePool;
    bool isV2;
}

struct ConvexStakingContext {
    address booster;
    address rewardPool;
    uint256 poolId;
    IERC20[] rewardTokens;
}

struct Curve2TokenConvexStrategyContext {
    StrategyContext baseStrategy;
    Curve2TokenPoolContext poolContext;
    ConvexStakingContext stakingContext;
}
