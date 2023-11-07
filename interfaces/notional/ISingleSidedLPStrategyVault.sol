// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.6;

import {SingleSidedRewardTradeParams} from "../../contracts/vaults/common/VaultTypes.sol";

struct InitParams {
    string name;
    uint16 borrowCurrencyId;
    StrategyVaultSettings settings;
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

interface ISingleSidedLPStrategyVault {
    struct SingleSidedLPStrategyVaultInfo {
        address pool;
        uint8 singleSidedTokenIndex;
        uint256 totalLPTokens;
        uint256 totalVaultShares;
    }

    function initialize(InitParams calldata params) external;

    function getStrategyVaultInfo() external view returns (SingleSidedLPStrategyVaultInfo memory);
    function emergencyExit(uint256 claimToExit, bytes calldata data) external;
    function restoreVault(uint256 minPoolClaim, bytes calldata data) external;
    function isLocked() external view returns (bool);

    function claimRewardTokens() external;
    function reinvestReward(
        SingleSidedRewardTradeParams[] calldata trades,
        uint256 minPoolClaim
    ) external returns (address rewardToken, uint256 amountSold, uint256 poolClaimAmount);
}
