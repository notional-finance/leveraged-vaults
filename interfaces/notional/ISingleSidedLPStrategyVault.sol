// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.6;

import {ITradingModule, Trade, TradeType} from "../trading/ITradingModule.sol";
import {IStrategyVault} from "./IStrategyVault.sol";
import {IERC20} from "../IERC20.sol";

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

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
}

/// @notice Common strategy vault settings
struct StrategyVaultSettings {
    /// @notice Slippage limit for emergency settlement (vault owns too much of the pool)
    uint32 deprecated_emergencySettlementSlippageLimitPercent;
    /// @notice Max share of the pool that the vault is allowed to hold
    uint16 maxPoolShare;
    /// @notice Limits the amount of allowable deviation from the oracle price
    uint16 oraclePriceDeviationLimitPercent;
    /// @notice Number of reward tokens
    uint8 numRewardTokens;
    /// @notice time in seconds after which claim will be triggered by account
    // if bot did not trigger it before
    uint32 forceClaimAfter;
}

interface ISingleSidedLPStrategyVault {
    /// @notice Emitted when vault settings are updated
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);
    /// @notice Emitted after an emergency exit
    event EmergencyExit(uint256 poolClaimExit, uint256[] exitBalances);
    /// @notice Emitted when the vault is locked
    event VaultLocked();
    /// @notice Emitted when the vault is unlocked
    event VaultUnlocked();

    struct SingleSidedLPStrategyVaultInfo {
        address pool;
        uint8 singleSidedTokenIndex;
        uint256 totalLPTokens;
        uint256 totalVaultShares;
        uint256 maxPoolShare;
        uint256 oraclePriceDeviationLimitPercent;
    }

    function initialize(InitParams calldata params) external;
    function TOKENS() external view returns (IERC20[] memory, uint8[] memory decimals);

    function getStrategyVaultInfo() external view returns (SingleSidedLPStrategyVaultInfo memory);
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings) external;
    function emergencyExit(uint256 claimToExit, bytes calldata data) external;
    function restoreVault(uint256 minPoolClaim, bytes calldata data) external;
    function isLocked() external view returns (bool);

    function reinvestReward(
        SingleSidedRewardTradeParams[] calldata trades,
        uint256 minPoolClaim
    ) external returns (address rewardToken, uint256 amountSold, uint256 poolClaimAmount);

    function tradeTokensBeforeRestore(SingleSidedRewardTradeParams[] calldata trades) external;
}