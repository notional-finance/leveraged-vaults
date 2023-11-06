// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";
import {StrategyVaultSettings} from "../../../interfaces/notional/ISingleSidedLPStrategyVault.sol";
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
    /// @notice min pool claim for slippage control
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
    /// @notice min pool claim for slippage control
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

/// @notice Proportional reinvestment trading parameters
struct Proportional2TokenRewardTradeParams {
    /// @notice Primary token trade params
    SingleSidedRewardTradeParams primaryTrade;
    /// @notice Secondary token trade params
    SingleSidedRewardTradeParams secondaryTrade;
}

/// @notice Composable reinvestment trading parameters
struct ComposableRewardTradeParams {
    /// @notice Trades for different reward tokens
    SingleSidedRewardTradeParams[] rewardTrades;
}

/// @notice Single-sided reinvestment trading parameters
struct SingleSidedRewardTradeParams {
    /// @notice Address of the token to sell (typically one of the reward tokens)
    address sellToken;
    /// @notice Address of the token to buy (typically one of the pool tokens)
    address buyToken;
    /// @notice Amount of tokens to sell
    uint256 amount;
    /// @notice Trade params
    TradeParams tradeParams;
}

/// @notice Base strategy context
struct StrategyContext {
    /// @notice Trading module proxy
    ITradingModule tradingModule;
    /// @notice Vault settings
    StrategyVaultSettings vaultSettings;
    /// @notice Vault state
    StrategyVaultState vaultState;
    /// @notice Precision used by the liquidity pool
    uint256 poolClaimPrecision;
    /// @notice Specifies if the vault can trade using static slippage
    bool canUseStaticSlippage;
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

/// @notice Pool context for 2-token pools (currently used by the Curve strategy)
struct TwoTokenPoolContext {
    /// @notice Primary token address
    address primaryToken;
    /// @notice Secondary token address
    address secondaryToken;
    /// @notice Primary token index
    uint8 primaryIndex;
    /// @notice Secondary token index
    uint8 secondaryIndex;
    /// @notice Primary token decimals
    uint8 primaryDecimals;
    /// @notice Secondary token decimals
    uint8 secondaryDecimals;
    /// @notice Primary token balance
    uint256 primaryBalance;
    /// @notice Secondary token balance
    uint256 secondaryBalance;
    /// @notice LP token address
    IERC20 poolToken;
}

/// @notice Composable pool context
struct ComposablePoolContext {
    /// @notice Pool tokens
    address[] tokens;
    /// @notice Token balances
    uint256[] balances;
    /// @notice Token decimals
    uint8[] decimals;
    /// @notice LP token address
    IERC20 poolToken;
    /// @notice Index of the primary token
    uint8 primaryIndex;
}
