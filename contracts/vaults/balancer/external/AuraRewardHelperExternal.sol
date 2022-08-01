// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {AuraStakingContext} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library AuraRewardHelperExternal {
    using TokenUtils for IERC20;

    function claimRewardTokens(
        AuraStakingContext memory context, 
        uint16 feePercentage, 
        address feeReceiver
    ) external returns (uint256[] memory claimedBalances) {
        claimedBalances = new uint256[](context.rewardTokens.length);
        for (uint256 i; i < context.rewardTokens.length; i++) {
            claimedBalances[i] = context.rewardTokens[i].balanceOf(address(this));
        }
        context.auraRewardPool.getReward(address(this), true);
        for (uint256 i; i < context.rewardTokens.length; i++) {
            claimedBalances[i] = context.rewardTokens[i].balanceOf(address(this)) - claimedBalances[i];

            if (claimedBalances[i] > 0 && feePercentage != 0 && feeReceiver != address(0)) {
                uint256 feeAmount = claimedBalances[i] * feePercentage / Constants.VAULT_PERCENT_BASIS;
                context.rewardTokens[i].checkTransfer(feeReceiver, feeAmount);
            }
        }
    }
}
