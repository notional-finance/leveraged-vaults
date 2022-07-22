// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {AuraStakingContext} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {RewardHelper} from "../internal/RewardHelper.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library AuraRewardHelperExternal {
    using TokenUtils for IERC20;

    function claimRewardTokens(
        AuraStakingContext memory context, 
        uint16 feePercentage, 
        address feeReceiver
    ) external {
        uint256 balBefore = context.balToken.balanceOf(address(this));
        context.auraRewardPool.getReward(address(this), true);
        uint256 balClaimed = context.balToken.balanceOf(address(this)) - balBefore;

        if (balClaimed > 0 && feePercentage != 0 && feeReceiver != address(0)) {
            uint256 feeAmount = balClaimed * feePercentage / Constants.VAULT_PERCENT_BASIS;
            context.balToken.checkTransfer(feeReceiver, feeAmount);
        }
    }
}
