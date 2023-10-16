// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

/// @notice Parameters for trades
struct TradeParams {
    /// @notice DEX ID
    uint16 dexId;
    /// @notice Trade type (i.e. Single/Batch)
    TradeType tradeType;
    /// @notice For dynamic trades, this field specifies the slippage percentage relative to
    /// the oracle price. For static trades, this field specifies the slippage limit amount.
    uint256 oracleSlippagePercentOrLimit;
    /// @notice Specifies if wrapped tokens (i.e. wstETH) should be unwrapped before trading
    bool tradeUnwrapped;
    /// @notice DEX specific data
    bytes exchangeData;
}

/// @notice Deposit trade parameters
struct DepositTradeParams {
    /// @notice Amount of primary tokens to sell
    uint256 tradeAmount;
    /// @notice Trade parameters
    TradeParams tradeParams;
}

/// @notice Deposit parameters
struct DepositParams {
    /// @notice Pool claim slippage control
    uint256 minPoolClaim;
    /// @notice DepositTradeParams or empty (single-sided entry)
    bytes tradeData;
}

/// @notice Redeem parameters
struct RedeemParams {
    /// @notice Primary token slippage control
    uint256 minPrimary;
    /// @notice Secondary token slippage control
    uint256 minSecondary;
    /// @notice TradeParams or empty (single-sided exit)
    bytes secondaryTradeParams;
}

/// @notice Deposit parameters for the composable pool
struct ComposableDepositParams {
    /// @notice Pool claim slippage control
    uint256 minPoolClaim;
    /// @notice Deposit trades or empty (single-sided entry)
    DepositTradeParams[] depositTrades;
}

/// @notice Redeem parameters for the composable pool
struct ComposableRedeemParams {
    /// @notice min amounts for slippage control
    uint256[] minAmounts;
    /// @notice Redemption trades or empty (single-sided exit)
    TradeParams[] redemptionTrades;
}

/// @notice Reward reinvestment parameters
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

/// @notice Base strategy context
struct StrategyContext {
    ITradingModule tradingModule;
    StrategyVaultSettings vaultSettings;
    StrategyVaultState vaultState;
    uint256 poolClaimPrecision;
    bool canUseStaticSlippage;
}

/// @notice Common strategy vault settings
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

/// @notice Common strategy vault state
struct StrategyVaultState {
    /// @notice Total number of pool tokens
    uint256 totalPoolClaim;
    /// @notice Total number of vault shares across all maturities
    uint80 totalVaultSharesGlobal;
    /// @notice Timestamp of previous settlement
    uint32 lastSettlementTimestamp;
    /// @notice Vault flags
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