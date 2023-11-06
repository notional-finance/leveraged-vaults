// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.7.6;

import {
    ReinvestRewardParams
} from "../../contracts/vaults/common/VaultTypes.sol";

interface ISingleSidedLPStrategyVault {
    struct SingleSidedLPStrategyVaultInfo {
        address pool;
        uint8 singleSidedTokenIndex;
        uint256 totalLPTokens;
        uint256 totalVaultShares;
    }

    function getStrategyVaultInfo() external view returns (SingleSidedLPStrategyVaultInfo memory);
    function emergencyExit(uint256 claimToExit, bytes calldata data) external;
    function restoreVault(uint256 minPoolClaim, bytes calldata data) external;
    function isLocked() external view returns (bool);

    function claimRewardTokens() external;
    function reinvestReward(ReinvestRewardParams calldata params) external returns (
        address rewardToken, uint256 amountSold, uint256 poolClaimAmount
    );
}
