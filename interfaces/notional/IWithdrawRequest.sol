// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

struct WithdrawRequest {
    uint256 requestId;
    uint256 vaultShares;
    bool hasSplit;
}

struct SplitWithdrawRequest {
    uint256 totalVaultShares; // uint64
    uint256 totalWithdraw; // uint184?
    bool finalized;
}