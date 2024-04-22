// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {IweETH, IeETH, ILiquidityPool, IWithdrawRequestNFT} from "@interfaces/etherfi/IEtherFi.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {VaultStorage} from "@contracts/vaults/common/VaultStorage.sol";
import {
    WithdrawRequest,
    SplitWithdrawRequest
} from "@contracts/vaults/common/WithdrawRequestBase.sol";

IweETH constant weETH = IweETH(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
IeETH constant eETH = IeETH(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
ILiquidityPool constant LiquidityPool = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
IWithdrawRequestNFT constant WithdrawRequestNFT = IWithdrawRequestNFT(0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c);

library EtherFiLib {
    function _initiateWithdrawImpl(
        uint256 weETHToUnwrap
    ) internal returns (uint256 requestId) {
        uint256 eETHReceived = weETH.unwrap(weETHToUnwrap);

        eETH.approve(address(LiquidityPool), eETHReceived);
        return LiquidityPool.requestWithdraw(address(this), eETHReceived);
    }

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,
        uint256 weETHPrice,
        uint256 borrowPrecision,
        uint256 exchangeRatePrecision
    ) internal view returns (uint256 ethValue) {
        if (w.requestId == 0) return 0;

        if (w.hasSplit) {
            SplitWithdrawRequest memory s = VaultStorage.getSplitWithdrawRequest()[w.requestId];
            // Check if the withdraw request has been claimed if the
            // request has been split, the value is the share of the ETH
            // claimed with no discount b/c the ETH is already held in the
            // vault contract.
            if (WithdrawRequestNFT.ownerOf(w.requestId) == address(0)) {
                return (s.totalWithdraw * w.vaultShares) / s.totalVaultShares;
            } else {
                return (w.vaultShares * weETHPrice * borrowPrecision) /
                    (s.totalVaultShares * exchangeRatePrecision);
            }
        }

        return (w.vaultShares * weETHPrice * borrowPrecision) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * exchangeRatePrecision);
    }

    function _finalizeWithdrawImpl(
        uint256 requestId
    ) internal returns (uint256 tokensClaimed, bool finalized) {
        finalized = (
            WithdrawRequestNFT.isFinalized(requestId) &&
            WithdrawRequestNFT.ownerOf(requestId) != address(0)
        );

        if (finalized) {
            uint256 balanceBefore = address(this).balance;
            WithdrawRequestNFT.claimWithdraw(requestId);
            tokensClaimed = address(this).balance - balanceBefore;
        }
    }

}