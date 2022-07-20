// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IStrategyVault} from "../../../interfaces/notional/IStrategyVault.sol";
import {VaultConfig} from "../../../interfaces/notional/IVaultController.sol";
import {IAuraBooster} from "../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../interfaces/aura/IAuraRewardPool.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerVault} from "../../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../../interfaces/balancer/IBalancerMinter.sol";
import {IBalancerPool} from "../../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

struct DeploymentParams {
    uint16 secondaryBorrowCurrencyId;
    bytes32 balancerPoolId;
    ILiquidityGauge liquidityGauge;
    IAuraBooster auraBooster;
    IAuraRewardPool auraRewardPool;
    uint256 auraPoolId;
    address stakedBalancerPoolToken;
    address auraToken;
    ITradingModule tradingModule;
    uint32 settlementPeriodInSeconds;
    address feeReceiver;
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
    TradeType tradeType;
    uint16 oracleSlippagePercent;
    bytes exchangeData;
}

struct OracleContext {
    uint256 oracleWindowInSeconds;
    uint256 balancerOracleWeight;
    uint256 primaryWeight;
    uint256 secondaryWeight;
    uint8 primaryDecimals;
    uint8 secondaryDecimals;
    PoolContext poolContext;
}

/// @notice Balancer pool related fields
struct PoolContext {
    IBalancerPool pool;
    bytes32 poolId;
    address primaryToken;
    address secondaryToken;
    uint8 primaryIndex;
    ILiquidityGauge liquidityGauge;
    IAuraBooster auraBooster;
    IAuraRewardPool auraRewardPool;
    uint256 auraPoolId;
    IERC20 balToken;
    IERC20 auraToken;
}

struct NormalSettlementContext {
    uint16 secondaryBorrowCurrencyId;
    uint256 maxUnderlyingSurplus;
    uint256 primarySettlementBalance;
    uint256 secondarySettlementBalance;
    uint256 redeemStrategyTokenAmount;
    int256 underlyingCashRequiredToSettle;
    uint256 debtSharesToRepay;
    /// @notice Amount of secondary fCash borrowed in external precision
    uint256 borrowedSecondaryfCashAmountExternal;
    PoolContext poolContext;
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

struct StrategyVaultSettings {
    uint256 maxUnderlyingSurplus;
    /// @notice Balancer oracle window in seconds
    uint32 oracleWindowInSeconds;
    uint16 maxBalancerPoolShare;
    /// @notice Slippage limit for normal settlement
    uint16 settlementSlippageLimitPercent;
    /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
    uint16 postMaturitySettlementSlippageLimitPercent;
    uint16 balancerOracleWeight;
    /// @notice Cool down in minutes for normal settlement
    uint16 settlementCoolDownInMinutes;
    /// @notice Cool down in minutes for post maturity settlement
    uint16 postMaturitySettlementCoolDownInMinutes;
    /// @notice Determines the amount of BAL transferred to FEE_RECEIVER
    uint16 feePercentage;
}

struct StrategyVaultState {
    /// @notice Total number of strategy tokens across all maturities
    uint256 totalStrategyTokenGlobal;
    uint32 lastSettlementTimestamp;
    uint32 lastPostMaturitySettlementTimestamp;
}

struct SettlementState {
    uint256 primarySettlementBalance;
    uint256 secondarySettlementBalance;
    uint256 strategyTokensRedeemed;
}
