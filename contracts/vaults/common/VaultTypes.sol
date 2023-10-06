// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

/// @notice Parameters for trades
struct TradeParams {
    uint16 dexId;
    TradeType tradeType;
    uint256 oracleSlippagePercentOrLimit;
    bool tradeUnwrapped;
    bytes exchangeData;
}

struct DepositTradeParams {
    uint256 tradeAmount;
    TradeParams tradeParams;
}

struct DepositParams {
    uint256 minPoolClaim;
    bytes tradeData;
}

struct RedeemParams {
    uint256 minPrimary;
    uint256 minSecondary;
    bytes secondaryTradeParams;
}

struct ComposableDepositParams {
    uint256 minPoolClaim;
    DepositTradeParams[] depositTrades;
}

struct ComposableRedeemParams {
    uint256[] minAmounts;
    TradeParams[] redemptionTrades;
}

struct ReinvestRewardParams {
    bytes tradeData;
    uint256 minPoolClaim;
}

struct Proportional2TokenRewardTradeParams {
    SingleSidedRewardTradeParams primaryTrade;
    SingleSidedRewardTradeParams secondaryTrade;
}

struct ComposableRewardTradeParams {
    SingleSidedRewardTradeParams[] rewardTrades;
}

struct SingleSidedRewardTradeParams {
    address sellToken;
    address buyToken;
    uint256 amount;
    TradeParams tradeParams;
}

struct StrategyContext {
    ITradingModule tradingModule;
    StrategyVaultSettings vaultSettings;
    StrategyVaultState vaultState;
    uint256 poolClaimPrecision;
    bool canUseStaticSlippage;
}

struct StrategyVaultSettings {
    /// @notice Slippage limit for emergency settlement (vault owns too much of the pool)
    uint32 emergencySettlementSlippageLimitPercent;
    /// @notice Max share of the pool that the vault is allowed to hold
    uint16 maxPoolShare;
    /// @notice Limits the amount of allowable deviation from the oracle price
    uint16 oraclePriceDeviationLimitPercent;
    /// @notice Slippage limit for joining/exiting pools
    uint16 poolSlippageLimitPercent;
}

struct StrategyVaultState {
    uint256 totalPoolClaim;
    /// @notice Total number of strategy tokens across all maturities
    uint80 totalVaultSharesGlobal;
    uint32 lastSettlementTimestamp;
    uint32 flags;
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
    IERC20 poolToken;
}

struct ComposablePoolContext {
    address[] tokens;
    uint256[] balances;
    uint8[] decimals;
    IERC20 poolToken;
    uint8 primaryIndex;
}