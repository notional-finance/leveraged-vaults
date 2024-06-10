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

interface ILidoWithdraw {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function requestWithdrawals(uint256[] memory _amounts, address _owner) external returns (uint256[] memory requestIds);
    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory requestsIds);
    function getWithdrawalStatus(uint256[] memory _requestIds) external view returns (WithdrawalRequestStatus[] memory statuses);
    function claimWithdrawal(uint256 _requestId) external;
    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
    function getLastRequestId() external view returns (uint256);
}

IERC20 constant rsETH = IERC20(0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7);
IWithdrawalManager constant WithdrawManager = IWithdrawalManager(0x62De59c08eB5dAE4b7E6F7a8cAd3006d6965ec16);
address constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
ILidoWithdraw constant LidoWithdraw = ILidoWithdraw(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

contract KelpCooldownHolder is ClonedCoolDownHolder {
    bool public triggered = false;

    constructor(address _vault) ClonedCoolDownHolder(_vault) { }

    receive() external payable {}

    /// @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown() internal override {
        uint256 balance = rsETH.balanceOf(address(this));
        rsETH.approve(address(WithdrawManager), balance);
        // initiate withdraw from Kelp
        WithdrawManager.initiateWithdrawal(stETH, balance);
    }

    /// @notice this method need to be called once withdraw on Kelp is finalized
    /// to start withdraw process from Lido so we can unwrap stETH to ETH
    /// since we are not able to withdraw ETH directly from Kelp
    function triggerExtraStep() external {
        require(!triggered);
        (/* */, /* */, /* */, uint256 userWithdrawalRequestNonce) = WithdrawManager.getUserWithdrawalRequest(stETH, address(this), 0);
        require(userWithdrawalRequestNonce < WithdrawManager.nextLockedNonce(stETH));

        WithdrawManager.completeWithdrawal(stETH);
        uint256 tokensClaimed = IERC20(stETH).balanceOf(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = tokensClaimed;
        IERC20(stETH).approve(address(LidoWithdraw), amounts[0]);
        LidoWithdraw.requestWithdrawals(amounts, address(this));

        triggered = true;
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        if (!triggered) {
            return (0, false);
        }

        uint256[] memory requestIds = LidoWithdraw.getWithdrawalRequests(address(this));
        ILidoWithdraw.WithdrawalRequestStatus[] memory withdrawsStatus = LidoWithdraw.getWithdrawalStatus(requestIds);

        if (!withdrawsStatus[0].isFinalized) {
            return (0, false);
        }

        LidoWithdraw.claimWithdrawal(requestIds[0]);

        tokensClaimed = address(this).balance;
        (bool sent,) = vault.call{value: tokensClaimed}("");
        require(sent);
        finalized = true;
    }
}

library KelpLib {
    using TypeConvert for int256;

    uint256 internal constant stETH_PRECISION = 1e18;

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,
        address borrowToken,
        uint256 borrowPrecision
    ) internal view returns (uint256) {
        address holder = address(uint160(w.requestId));

        uint256 expectedStETHAmount;
        if (KelpCooldownHolder(payable(holder)).triggered()) {
            uint256[] memory requestIds = LidoWithdraw.getWithdrawalRequests(holder);
            ILidoWithdraw.WithdrawalRequestStatus[] memory withdrawsStatus = LidoWithdraw.getWithdrawalStatus(requestIds);

            expectedStETHAmount = withdrawsStatus[0].amountOfStETH;
        } else {
            (/* */, expectedStETHAmount, /* */, /* */) = WithdrawManager.getUserWithdrawalRequest(stETH, holder, 0);

        }

        (int256 stETHToBorrowRate, /* */) = Deployments.TRADING_MODULE.getOraclePrice(
            address(stETH), borrowToken
        );

        return (expectedStETHAmount * stETHToBorrowRate.toUint() * borrowPrecision) /
            (Constants.EXCHANGE_RATE_PRECISION * stETH_PRECISION);
    }

    function _initiateWithdrawImpl(
        uint256 balanceToTransfer,
        address holderImplementation
    ) internal returns (uint256 requestId) {
        KelpCooldownHolder holder = KelpCooldownHolder(payable(Clones.clone(holderImplementation)));
        rsETH.transfer(address(holder), balanceToTransfer);
        holder.startCooldown();

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
        if (!KelpCooldownHolder(payable(holder)).triggered()) return false;

        uint256[] memory requestIds = LidoWithdraw.getWithdrawalRequests(holder);
        ILidoWithdraw.WithdrawalRequestStatus[] memory withdrawsStatus = LidoWithdraw.getWithdrawalStatus(requestIds);

        return withdrawsStatus[0].isFinalized;
    }

    function _canTriggerExtraStep(uint256 requestId) internal view returns (bool) {
        address holder = address(uint160(requestId));
        if (KelpCooldownHolder(payable(holder)).triggered()) return false;

        (/* */, /* */, /* */, uint256 userWithdrawalRequestNonce) = WithdrawManager.getUserWithdrawalRequest(stETH, holder, 0);

        return userWithdrawalRequestNonce < WithdrawManager.nextLockedNonce(stETH);
    }

    function _triggerExtraStep(uint256 requestId) internal  {
        KelpCooldownHolder holder = KelpCooldownHolder(payable(address(uint160(requestId))));
        holder.triggerExtraStep();
    }
}