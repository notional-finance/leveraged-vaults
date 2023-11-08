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
    DepositTradeParams[] depositTrades;
}

/// @notice Redeem parameters
struct RedeemParams {
    /// @notice min amounts for slippage control
    uint256[] minAmounts;
    /// @notice Redemption trades or empty (single-sided exit)
    TradeParams[] redemptionTrades;
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