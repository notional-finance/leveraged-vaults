// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ITradingModule, Trade, TradeType} from "../../../interfaces/trading/ITradingModule.sol";

/// @notice Parameters for trades
struct TradeParams {
    uint16 dexId;
    TradeType tradeType;
    uint256 oracleSlippagePercentOrLimit;
    bool tradeUnwrapped;
    bytes exchangeData;
}

struct StrategyContext {
    uint32 settlementPeriodInSeconds;
    ITradingModule tradingModule;
    StrategyVaultSettings vaultSettings;
    StrategyVaultState vaultState;
    uint256 poolClaimPrecision;
}

struct StrategyVaultSettings {
    uint256 maxUnderlyingSurplus;
    /// @notice Slippage limit for normal settlement
    uint32 settlementSlippageLimitPercent;
    /// @notice Slippage limit for post maturity settlement
    uint32 postMaturitySettlementSlippageLimitPercent;
    /// @notice Slippage limit for emergency settlement (vault owns too much of the pool)
    uint32 emergencySettlementSlippageLimitPercent;
    /// @notice Slippage limit for selling reward tokens
    uint32 maxRewardTradeSlippageLimitPercent;
    /// @notice Max share of the pool that the vault is allowed to hold
    uint16 maxPoolShare;
    /// @notice Cool down in minutes for normal settlement
    uint16 settlementCoolDownInMinutes;
    /// @notice Limits the amount of allowable deviation from the oracle price
    uint16 oraclePriceDeviationLimitPercent;
    /// @notice Slippage limit for joining/exiting pools
    uint16 poolSlippageLimitPercent;
}

struct StrategyVaultState {
    uint256 totalPoolClaim;
    /// @notice Total number of strategy tokens across all maturities
    uint80 totalStrategyTokenGlobal;
    uint32 lastSettlementTimestamp;
}
