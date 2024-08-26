// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import { WithdrawRequest } from "@contracts/vaults/common/WithdrawRequestBase.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ClonedCoolDownHolder} from "./ClonedCoolDownHolder.sol";

interface IWithdrawalManager {
    function initiateWithdrawal(address asset, uint256 withdrawAmount) external;
    function completeWithdrawal(address asset) external payable;
    function nextLockedNonce(address asset) external view returns (uint256 requestNonce);
    function withdrawalDelayBlocks() external view returns (uint256);
    function getUserWithdrawalRequest(address asset, address user, uint256 userIndex)
        external
        view
        returns (uint256 rsETHAmount, uint256 expectedAssetAmount, uint256 withdrawalStartBlock, uint256 userNonce);
    function unlockQueue(
        address asset,
        uint256 firstExcludedIndex,
        uint256 minimumAssetPrice,
        uint256 minimumRsEthPrice
    ) external returns (uint256 rsETHBurned, uint256 assetAmountUnlocked);
}

IERC20 constant rsETH = IERC20(0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7);
IWithdrawalManager constant WithdrawManager = IWithdrawalManager(0x62De59c08eB5dAE4b7E6F7a8cAd3006d6965ec16);

contract KelpCooldownHolder is ClonedCoolDownHolder {
    bool public triggered = false;

    constructor(address _vault) ClonedCoolDownHolder(_vault) { }

    receive() external payable {}

    /// @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown(uint256 cooldownBalance) internal override {
        rsETH.approve(address(WithdrawManager), cooldownBalance);
        // initiate withdraw from Kelp
        WithdrawManager.initiateWithdrawal(Deployments.ALT_ETH_ADDRESS, cooldownBalance);
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        (/* */, /* */, uint256 userWithdrawalStartBlock, uint256 userWithdrawalRequestNonce) = WithdrawManager.getUserWithdrawalRequest(Deployments.ALT_ETH_ADDRESS, address(this), 0);
        uint256 nextNonce = WithdrawManager.nextLockedNonce(Deployments.ALT_ETH_ADDRESS);
        // These two requirements are checked in the WithdrawManager.
        if (
            nextNonce < userWithdrawalRequestNonce || 
            block.number < userWithdrawalStartBlock + WithdrawManager.withdrawalDelayBlocks()
        ) {
            return (0, false);
        }

        uint256 balanceBefore = address(this).balance;
        WithdrawManager.completeWithdrawal(Deployments.ALT_ETH_ADDRESS);
        uint256 balanceAfter = address(this).balance;

        tokensClaimed = balanceAfter - balanceBefore;
        (bool sent,) = vault.call{value: tokensClaimed}("");
        require(sent);
        finalized = true;
    }
}

library KelpLib {
    using TypeConvert for int256;

    function _getValueOfWithdrawRequest(
        uint256 totalVaultShares,
        address borrowToken,
        uint256 borrowPrecision
    ) internal view returns (uint256) {
        (int256 rsETHPrice, /* */) = Deployments.TRADING_MODULE.getOraclePrice(address(rsETH), borrowToken);
        return (totalVaultShares * rsETHPrice.toUint() * borrowPrecision) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * Constants.EXCHANGE_RATE_PRECISION);
    }

    function _initiateWithdrawImpl(
        uint256 balanceToTransfer,
        address holderImplementation
    ) internal returns (uint256 requestId) {
        KelpCooldownHolder holder = KelpCooldownHolder(payable(Clones.clone(holderImplementation)));
        rsETH.transfer(address(holder), balanceToTransfer);
        holder.startCooldown(balanceToTransfer);

        return uint256(uint160(address(holder)));
    }

    function _finalizeWithdrawImpl(
        uint256 requestId
    ) internal returns (uint256 tokensClaimed, bool finalized) {
        KelpCooldownHolder holder = KelpCooldownHolder(payable(address(uint160(requestId))));
        (tokensClaimed, finalized) = holder.finalizeCooldown();
    }

    function _canFinalizeWithdrawRequest(uint256 requestId) internal view returns (bool) {
        address holder = address(uint160(requestId));
        (/* */, /* */, uint256 userWithdrawalStartBlock, uint256 userWithdrawalRequestNonce) = WithdrawManager.getUserWithdrawalRequest(Deployments.ALT_ETH_ADDRESS, holder, 0);
        uint256 nextNonce = WithdrawManager.nextLockedNonce(Deployments.ALT_ETH_ADDRESS);
        return (
            userWithdrawalRequestNonce < nextNonce &&
            (userWithdrawalStartBlock + WithdrawManager.withdrawalDelayBlocks()) < block.number
        );
    }
}