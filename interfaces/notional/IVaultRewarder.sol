// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import { StrategyVaultSettings } from "./ISingleSidedLPStrategyVault.sol";
// Per Reward Token state of accumulators
struct VaultRewardState {
    address rewardToken;
    uint32 lastAccumulatedTime;
    uint32 endTime;
    // Slot #2
    // If secondary rewards are enabled, they will be streamed to the accounts via
    // an annual emission rate. If the same reward token is also issued by the LP pool,
    // those tokens will be added on top of the annual emission rate. If the vault is under
    // automatic reinvestment mode, the secondary reward token cannot be sold.
    uint128 emissionRatePerYear; // in internal token precision
    uint128 accumulatedRewardPerVaultShare;
}

enum RewardPoolType {
    _UNUSED,
    AURA,
    CONVEX_MAINNET,
    CONVEX_ARBITRUM
}

struct RewardPoolStorage {
    RewardPoolType poolType;
    address rewardPool;
    uint32 lastClaimTimestamp;
}

interface IVaultRewarder {
    event VaultRewardTransfer(address token, address account, uint256 amount);
    event VaultRewardUpdate(address rewardToken, uint128 emissionRatePerYear, uint32 endTime);

    function getRewardSettings() external view returns (
        VaultRewardState[] memory v, StrategyVaultSettings memory s, RewardPoolStorage memory r
    );

    function getRewardDebt(address rewardToken, address account) external view returns (
        uint256 rewardDebt
    );

    function getAccountRewardClaim(address account, uint256 blockTime) external view returns (
        uint256[] memory rewards
    );

    function updateRewardToken(
        uint256 index,
        address rewardToken,
        uint128 emissionRatePerYear,
        uint32 endTime
    ) external;

    // Callable by account to claim their own rewards
    function claimAccountRewards(address account) external;

    function claimRewardTokens() external;
}