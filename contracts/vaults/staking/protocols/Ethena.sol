// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {IsUSDe} from "@interfaces/ethena/IsUSDe.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {VaultStorage} from "@contracts/vaults/common/VaultStorage.sol";
import {
    WithdrawRequest,
    SplitWithdrawRequest
} from "@contracts/vaults/common/WithdrawRequestBase.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ClonedCoolDownHolder} from "./ClonedCoolDownHolder.sol";

IsUSDe constant sUSDe = IsUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
IERC20 constant USDe = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

contract EthenaCooldownHolder is ClonedCoolDownHolder {

    constructor(address _vault) ClonedCoolDownHolder(_vault) { }

    /// @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown() internal override {
        uint24 duration = sUSDe.cooldownDuration();
        uint256 balance = sUSDe.balanceOf(address(this));
        if (duration == 0) {
            // If the cooldown duration is set to zero, can redeem immediately
            sUSDe.redeem(balance, address(this), address(this));
        } else {
            // If we execute a second cooldown while one exists, the cooldown end
            // will be pushed further out. This holder should only ever have one
            // cooldown ever.
            require(sUSDe.cooldowns(address(this)).cooldownEnd == 0);
            sUSDe.cooldownShares(balance);
        }
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        uint24 duration = sUSDe.cooldownDuration();
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(address(this));

        if (block.timestamp < userCooldown.cooldownEnd && 0 < duration) {
            // Do not revert if the cooldown has not completed, will return a false
            // for the finalized state.
            return (0, false);
        }

        // If a cooldown has been initiated, need to call unstake to complete it. If
        // duration was set to zero then the USDe will be on this contract already.
        if (0 < userCooldown.cooldownEnd) {
            sUSDe.unstake(address(this));
        }

        // USDe is immutable. It cannot have a transfer tax and it is ERC20 compliant
        // so we do not need to use the additional protections here.
        tokensClaimed = USDe.balanceOf(address(this));
        USDe.transfer(vault, tokensClaimed);
        finalized = true;
    }
}

library EthenaLib {

    /// @notice This vault will always borrow USDe so the value returned in this method will
    /// always be USDe.
    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,
        uint256 /* stakeAssetPrice */
    ) internal view returns (uint256 usdEValue) {
        if (w.hasSplit) {
            SplitWithdrawRequest memory s = VaultStorage.getSplitWithdrawRequest()[w.requestId];
            if (s.finalized) {
                // totalWithdraw is a USDe amount
                return (s.totalWithdraw * w.vaultShares) / s.totalVaultShares;
            }
        }

        address holder = address(uint160(w.requestId));
        // This valuation is the amount of USDe the account will receive at cooldown, once
        // a cooldown is initiated the account is no longer receiving sUSDe yield. This balance
        // of USDe is transferred to a Silo contract and guaranteed to be available once the
        // cooldown has passed.
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(holder);

        return userCooldown.underlyingAmount;
        /*
        // This is the current valuation of sUSDe at the current market price. If the cooldown
        // time window is extended, the price of sUSDe may drop relative to the price of USDe
        // which would reflect the current market expectation around redeeming sUSDe.
        uint256 valuation = (w.vaultShares * stakeAssetPrice * STAKING_PRECISION) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * 1e18);

        return SafeUint256.min(userCooldown.underlyingAmount, valuation);
        */
    }

    function _initiateWithdrawImpl(
        uint256 balanceToTransfer,
        address holderImplementation
    ) internal returns (uint256 requestId) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(Clones.clone(holderImplementation));
        sUSDe.transfer(address(holder), balanceToTransfer);
        holder.startCooldown();

        return uint256(uint160(address(holder)));
    }

    function _finalizeWithdrawImpl(
        uint256 requestId
    ) internal returns (uint256 tokensClaimed, bool finalized) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(address(uint160(requestId)));
        (tokensClaimed, finalized) = holder.finalizeCooldown();
    }
}