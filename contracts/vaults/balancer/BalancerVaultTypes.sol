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
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {IAsset} from "../../../interfaces/balancer/IBalancerVault.sol";
import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

struct DeploymentParams {
    bytes32 balancerPoolId;
    ILiquidityGauge liquidityGauge;
    ITradingModule tradingModule;
    uint32 settlementPeriodInSeconds;
    address feeReceiver;
}

struct AuraDeploymentParams {
    uint16 primaryBorrowCurrencyId;
    uint16 secondaryBorrowCurrencyId;
    IAuraRewardPool auraRewardPool;
    DeploymentParams baseParams;
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
    bytes tradeData;
}

struct DepositTradeParams {
    uint16 dexId;
    Trade trade;
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
    uint32 oracleSlippagePercent;
    bytes exchangeData;
}

/// @notice Parameters for joining/exiting Balancer pools
struct PoolParams {
    IAsset[] assets;
    uint256[] amounts;
    uint256 msgValue;
}

struct OracleContext {
    uint256 oracleWindowInSeconds;
    uint256 balancerOracleWeight;
}

struct WeightedOracleContext {
    uint256[] weights;
    OracleContext baseOracle;
}

struct StableOracleContext {
    /// @notice Amplification parameter
    uint256 ampParam;
    OracleContext baseOracle;
}

struct BoostedOracleContext {
    /// @notice Amplification parameter
    uint256 ampParam;
    /// @notice BPT balance in the pool
    uint256 bptBalance;
    /// @notice Protocol fee amount used to calculate the virtual supply
    uint256 dueProtocolFeeBptAmount;
}

/// @notice Balancer pool related fields
struct PoolContext {
    IERC20 pool;
    bytes32 poolId;
}

struct AuraStakingContext {
    ILiquidityGauge liquidityGauge;
    IAuraBooster auraBooster;
    IAuraRewardPool auraRewardPool;
    uint256 auraPoolId;
    IERC20[] rewardTokens;
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

struct ThreeTokenPoolContext {
    address tertiaryToken;
    uint8 tertiaryIndex;
    uint8 tertiaryDecimals;
    uint256 tertiaryBalance;
    TwoTokenPoolContext basePool;
}

struct StrategyContext {
    uint256 totalBPTHeld;
    uint16 secondaryBorrowCurrencyId;
    ITradingModule tradingModule;
    StrategyVaultSettings vaultSettings;
    StrategyVaultState vaultState;
}

struct Weighted2TokenAuraStrategyContext {
    TwoTokenPoolContext poolContext;
    WeightedOracleContext oracleContext;
    AuraStakingContext stakingContext;
    StrategyContext baseStrategy;
}

struct MetaStable2TokenAuraStrategyContext {
    TwoTokenPoolContext poolContext;
    StableOracleContext oracleContext;
    AuraStakingContext stakingContext;
    StrategyContext baseStrategy;
}

struct Boosted3TokenAuraStrategyContext {
    ThreeTokenPoolContext poolContext;
    BoostedOracleContext oracleContext;
    AuraStakingContext stakingContext;
    StrategyContext baseStrategy;
}

struct TwoTokenAuraSettlementContext {
    StrategyContext strategyContext;
    OracleContext oracleContext;
    TwoTokenPoolContext poolContext;
    AuraStakingContext stakingContext;
}

struct ThreeTokenAuraSettlementContext {
    StrategyContext strategyContext;
    ThreeTokenPoolContext poolContext;
    AuraStakingContext stakingContext;
}

struct NormalSettlementData {
    uint16 secondaryBorrowCurrencyId;
    uint256 maxUnderlyingSurplus;
    uint256 primarySettlementBalance;
    uint256 secondarySettlementBalance;
    uint256 redeemStrategyTokenAmount;
    int256 underlyingCashRequiredToSettle;
    uint256 debtSharesToRepay;
    /// @notice Amount of secondary fCash borrowed in external precision
    uint256 borrowedSecondaryfCashAmountExternal;
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
    /// @notice Slippage limit for normal settlement
    uint32 settlementSlippageLimitPercent;
    /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
    uint32 postMaturitySettlementSlippageLimitPercent;
    uint16 maxBalancerPoolShare;
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
    uint80 totalStrategyTokenGlobal;
    uint32 lastSettlementTimestamp;
    uint32 lastPostMaturitySettlementTimestamp;
}

struct SettlementState {
    uint88 primarySettlementBalance;
    uint88 secondarySettlementBalance;
    uint80 strategyTokensRedeemed;
}
