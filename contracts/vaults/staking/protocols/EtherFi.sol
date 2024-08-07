// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {IweETH, IeETH, ILiquidityPool, IWithdrawRequestNFT} from "@interfaces/etherfi/IEtherFi.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {VaultStorage} from "@contracts/vaults/common/VaultStorage.sol";
import {
    WithdrawRequest,
    SplitWithdrawRequest
} from "@contracts/vaults/common/WithdrawRequestBase.sol";

// Mainnet Addresses
IweETH constant weETH = IweETH(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
IeETH constant eETH = IeETH(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
ILiquidityPool constant LiquidityPool = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
IWithdrawRequestNFT constant WithdrawRequestNFT = IWithdrawRequestNFT(0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c);

library EtherFiLib {
    using TypeConvert for int256;

    function _initiateWithdrawImpl(uint256 weETHToUnwrap) internal returns (uint256 requestId) {
        uint256 balanceBefore = eETH.balanceOf(address(this));
        weETH.unwrap(weETHToUnwrap);
        uint256 balanceAfter = eETH.balanceOf(address(this));
        uint256 eETHReceived = balanceAfter - balanceBefore;

        eETH.approve(address(LiquidityPool), eETHReceived);
        return LiquidityPool.requestWithdraw(address(this), eETHReceived);
    }

    function _getValueOfWithdrawRequest(
        uint256 totalVaultShares,
        uint256 weETHPrice,
        uint256 borrowPrecision
    ) internal pure returns (uint256) {
        return (totalVaultShares * weETHPrice * borrowPrecision) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * Constants.EXCHANGE_RATE_PRECISION);
    }

    function _finalizeWithdrawImpl(
        uint256 requestId
    ) internal returns (uint256 tokensClaimed, bool finalized) {
        finalized = _canFinalizeWithdrawRequest(requestId);

        if (finalized) {
            uint256 balanceBefore = address(this).balance;
            WithdrawRequestNFT.claimWithdraw(requestId);
            tokensClaimed = address(this).balance - balanceBefore;
        }
    }

    function _canFinalizeWithdrawRequest(uint256 requestId) internal view returns (bool) {
        return (
            WithdrawRequestNFT.isFinalized(requestId) &&
            WithdrawRequestNFT.ownerOf(requestId) != address(0)
        );
    }
}