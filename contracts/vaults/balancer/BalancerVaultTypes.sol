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
import {ITradingModule, Trade} from "../../../interfaces/trading/ITradingModule.sol";

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

struct DepositParams {
    uint256 minBPT;
    uint256 secondaryfCashAmount;
    uint32 secondaryBorrowLimit;
    uint32 secondaryRollLendLimit;
}

struct RedeemParams {
    uint32 minSecondaryLendRate;
    uint256 minPrimary;
    uint256 minSecondary;
    bytes secondaryTradeParams;
}

struct SecondaryTradeParams {
    uint16 dexId;
    uint32 oracleSlippagePercent;
    bytes exchangeData;
}

struct BoostContext {
    ILiquidityGauge liquidityGauge;
    IBoostController boostController;
}

struct OracleContext {
    IBalancerPool pool;
    bytes32 poolId;
    uint256 oracleWindowInSeconds;
    uint256 primaryWeight;
    uint256 secondaryWeight;
    uint8 primaryIndex;
    uint8 primaryDecimals;
    uint8 secondaryDecimals;
}

/// @notice Balancer pool related fields
struct PoolContext {
    IBalancerPool pool;
    bytes32 poolId;
    address primaryToken;
    address secondaryToken;
    uint8 primaryIndex;
}

struct NormalSettlementContext {
    uint256 maxUnderlyingSurplus;
    uint256 primarySettlementBalance;
    uint256 secondarySettlementBalance;
    uint256 redeemStrategyTokenAmount;
    int256 underlyingCashRequiredToSettle;
    uint256 debtSharesToRepay;
    /// @notice Amount of secondary fCash borrowed in external precision
    uint256 borrowedSecondaryfCashAmountExternal;
    PoolContext poolContext;
    BoostContext boostContext;
}

struct RewardTokenTradeParams {
    uint16 primaryTradeDexId;
    Trade primaryTrade;
    uint16 secondaryTradeDexId;
    Trade secondaryTrade;
}

struct ReinvestRewardParams {
    bytes tradeData;
    uint256 minBPT;
}

struct VeBalDelegatorInfo {
    ILiquidityGauge liquidityGauge;
    IVeBalDelegator veBalDelegator;
    address balToken;
}

struct StrategyVaultSettings {
    uint256 maxUnderlyingSurplus;
    /// @notice Balancer oracle window in seconds
    uint32 oracleWindowInSeconds;
    uint16 maxBalancerPoolShare;
    /// @notice Slippage limit for normal settlement
    uint16 settlementSlippageLimitBPS;
    /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
    uint16 postMaturitySettlementSlippageLimitBPS;
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
