// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {
    VaultStorage,
    WithdrawRequest,
    SplitWithdrawRequest
} from "./VaultStorage.sol";
import { Deployments } from "@deployments/Deployments.sol";

abstract contract WithdrawRequestBase {
    event InitiateWithdrawRequest(
        address indexed account,
        bool indexed isForced,
        uint256 vaultShares,
        uint256 requestId
    );

    function _initiateWithdrawImpl(
        address account,
        uint256 vaultShares,
        bool isForced
    ) internal virtual returns (uint256 requestId);

    function _finalizeWithdrawImpl(
        address account,
        uint256 requestId
    ) internal virtual returns (uint256 tokensClaimed, bool finalized);

    function _stakeTokens(
        address account,
        uint256 depositUnderlyingExternal,
        uint256 maturity,
        bytes calldata data
    ) internal virtual returns (uint256 vaultShares);

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,
        uint256 stakeAssetPrice
    ) internal virtual view returns (uint256 borrowTokenValue);

    function getSplitWithdrawRequest(
        uint256 requestId
    ) public view returns (SplitWithdrawRequest memory s) {
        s = VaultStorage.getSplitWithdrawRequest()[requestId];
    }

    function getWithdrawRequests(
        address account
    ) public view returns (
        WithdrawRequest memory forcedWithdraw,
        WithdrawRequest memory accountWithdraw
    ) {
        forcedWithdraw = VaultStorage.getForcedWithdrawRequest()[account];
        accountWithdraw = VaultStorage.getAccountWithdrawRequest()[account];
    }

    function _initiateWithdraw(
        address account,
        uint256 vaultShares,
        bool isForced
    ) internal {
        uint256 accountVaultShares = Deployments.NOTIONAL.getVaultAccount(
            account, address(this)
        ).vaultShares;
        // Ensures that we do not over-withdraw vault shares.
        require(0 < accountVaultShares && vaultShares <= accountVaultShares);

        (
            WithdrawRequest memory forcedWithdraw,
            WithdrawRequest memory accountWithdraw
        ) = getWithdrawRequests(account);

        uint256 requestId;
        if (isForced) {
            require(forcedWithdraw.requestId == 0, "Existing Request");
            // Forced requests withdraw all remaining vault shares
            vaultShares = accountVaultShares - accountWithdraw.vaultShares;

            requestId = _initiateWithdrawImpl(account, vaultShares, isForced);
            forcedWithdraw.requestId = requestId;
            forcedWithdraw.hasSplit = false;
            forcedWithdraw.vaultShares = vaultShares;
            VaultStorage.getForcedWithdrawRequest()[account] = forcedWithdraw;
        } else {
            // Account cannot withdraw if there is an active forced withdraw
            require(
                accountWithdraw.requestId == 0 && forcedWithdraw.requestId == 0,
                "Existing Request"
            );

            requestId = _initiateWithdrawImpl(account, vaultShares, isForced);
            accountWithdraw.requestId = requestId;
            accountWithdraw.hasSplit = false;
            accountWithdraw.vaultShares = vaultShares;
            VaultStorage.getAccountWithdrawRequest()[account] = accountWithdraw;
        }

        emit InitiateWithdrawRequest(account, isForced, vaultShares, requestId);
    }

    function _redeemActiveWithdrawRequests(
        address account,
        WithdrawRequest memory accountWithdraw,
        WithdrawRequest memory forcedWithdraw
    ) internal returns (uint256 vaultSharesRedeemed, uint256 tokensClaimed) {
        if (accountWithdraw.requestId != 0) {
            (uint256 tokens, bool finalized) = _finalizeWithdraw(account, accountWithdraw);
            if (finalized) {
                vaultSharesRedeemed = accountWithdraw.vaultShares;
                tokensClaimed = tokens;
                delete VaultStorage.getAccountWithdrawRequest()[account];
            }
        }

        if (forcedWithdraw.requestId != 0) {
            (uint256 tokens, bool finalized) = _finalizeWithdraw(account, forcedWithdraw);
            if (finalized) {
                vaultSharesRedeemed = vaultSharesRedeemed + forcedWithdraw.vaultShares;
                tokensClaimed = tokensClaimed + tokens;
                delete VaultStorage.getForcedWithdrawRequest()[account];
            }
        }
    }

    function _finalizeWithdrawsOutOfBand(address account) internal {
        (
            WithdrawRequest memory forcedWithdraw,
            WithdrawRequest memory accountWithdraw
        ) = getWithdrawRequests(account);

        if (accountWithdraw.requestId != 0) {
            (uint256 tokens, bool finalized) = _finalizeWithdraw(account, accountWithdraw);

            if (!accountWithdraw.hasSplit && finalized) {
                VaultStorage.getSplitWithdrawRequest()[accountWithdraw.requestId] = SplitWithdrawRequest({
                    totalVaultShares: accountWithdraw.vaultShares,
                    totalWithdraw: tokens,
                    finalized: true
                });

                accountWithdraw.hasSplit = true;
                VaultStorage.getAccountWithdrawRequest()[account] = accountWithdraw;
            }
        }

        if (forcedWithdraw.requestId != 0) {
            (uint256 tokens, bool finalized) = _finalizeWithdraw(account, forcedWithdraw);

            if (!forcedWithdraw.hasSplit && finalized) {
                VaultStorage.getSplitWithdrawRequest()[forcedWithdraw.requestId] = SplitWithdrawRequest({
                    totalVaultShares: forcedWithdraw.vaultShares,
                    totalWithdraw: tokens,
                    finalized: true
                });

                forcedWithdraw.hasSplit = true;
                VaultStorage.getForcedWithdrawRequest()[account] = forcedWithdraw;
            }
        }
    }

    function _finalizeWithdraw(
        address account,
        WithdrawRequest memory w
    ) internal returns (uint256 tokensClaimed, bool finalized) {
        SplitWithdrawRequest memory s;
        if (w.hasSplit) {
            s = VaultStorage.getSplitWithdrawRequest()[w.requestId];

            // If the split request was already finalized in a different transaction
            // then return the values here and we can short circuit the withdraw impl
            if (s.finalized) {
                return (
                    s.totalWithdraw * w.vaultShares / s.totalVaultShares,
                    true
                );
            }
        }

        (tokensClaimed, finalized) = _finalizeWithdrawImpl(account, w.requestId);

        if (w.hasSplit && finalized) {
            s.totalWithdraw = tokensClaimed;
            s.finalized = true;
            VaultStorage.getSplitWithdrawRequest()[w.requestId] = s;

            tokensClaimed = s.totalWithdraw * w.vaultShares / s.totalVaultShares;
        } else if (!finalized) {
            // No tokens claimed if not finalized
            require(tokensClaimed == 0);
        }
    }

    /// @notice Splits a withdraw request during liquidation
    function _splitWithdrawRequest(
        address _from,
        address _to,
        uint256 totalVaultSharesBefore,
        uint256 requiredVaultShares
    ) internal {
        (
            WithdrawRequest memory forcedWithdraw,
            WithdrawRequest memory accountWithdraw
        ) = getWithdrawRequests(_from);

        // liquidVaultShares = total vault shares - f.vaultShares - a.vaultShares
        // requiredVaultShares = min(requiredVaultShares - liquidVaultShares, 0)
        uint256 liquidVaultShares = (
            totalVaultSharesBefore - forcedWithdraw.vaultShares - accountWithdraw.vaultShares
        );
        // No additional withdraw request shares required
        if (requiredVaultShares <= liquidVaultShares) return;

        requiredVaultShares = requiredVaultShares - liquidVaultShares;

        // The _to can only hold one withdraw request at a time, prefer the account withdraw
        // request since it will necessarily come first (a forced withdraw will withdraw all
        // vault shares and therefore an account withdraw is not possible afterwards).
        if (requiredVaultShares <= accountWithdraw.vaultShares) {
            _split(_from, _to, requiredVaultShares, accountWithdraw, false);
        } else if (requiredVaultShares <= forcedWithdraw.vaultShares) {
            _split(_from, _to, requiredVaultShares, forcedWithdraw, true);
        } else {
            revert("Cannot Transfer Withdraw");
        }
    }

    function _split(
        address _from,
        address _to,
        uint256 vaultShares,
        WithdrawRequest memory w,
        bool forcedRequest
    ) private {
        mapping(address => WithdrawRequest) storage store = forcedRequest ?
          VaultStorage.getForcedWithdrawRequest() :
          VaultStorage.getAccountWithdrawRequest();

        if (!w.hasSplit) {
            SplitWithdrawRequest memory s = VaultStorage.getSplitWithdrawRequest()[w.requestId];
            require(s.finalized == false && s.totalVaultShares == 0);
            VaultStorage.getSplitWithdrawRequest()[w.requestId].totalVaultShares = w.vaultShares;
        }

        if (w.vaultShares == vaultShares) {
            // If the resulting vault shares is zero, then delete the request
            delete store[_from];
        } else {
            store[_from] = WithdrawRequest({
                requestId: w.requestId,
                vaultShares: w.vaultShares - vaultShares,
                hasSplit: true
            });
        }

        // Ensure that no withdraw request gets overridden
        WithdrawRequest storage toWithdraw =
            forcedRequest ? VaultStorage.getAccountWithdrawRequest()[_to] : store[_to];
        require(toWithdraw.requestId == 0 || toWithdraw.requestId == w.requestId , "Existing Request");

        // Either the request gets set or it gets incremented here.
        toWithdraw.requestId = w.requestId;
        toWithdraw.vaultShares = toWithdraw.vaultShares + vaultShares;
        toWithdraw.hasSplit = true;
    }
}