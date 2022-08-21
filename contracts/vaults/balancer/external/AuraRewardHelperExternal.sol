// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {AuraStakingContext} from "../BalancerVaultTypes.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";

library AuraRewardHelperExternal {
    using TokenUtils for IERC20;

    function claimRewardTokens(
        // @audit switch this to calldata
        AuraStakingContext memory context, 
        uint16 feePercentage, 
        address feeReceiver
    ) external returns (uint256[] memory claimedBalances) {
        claimedBalances = new uint256[](context.rewardTokens.length);
        // @audit cache length, switch plus plus
        for (uint256 i; i < context.rewardTokens.length; i++) {
            claimedBalances[i] = context.rewardTokens[i].balanceOf(address(this));
        }
        context.auraRewardPool.getReward(address(this), true);
        for (uint256 i; i < context.rewardTokens.length; i++) {
            claimedBalances[i] = context.rewardTokens[i].balanceOf(address(this)) - claimedBalances[i];

            if (claimedBalances[i] > 0 && feePercentage != 0 && feeReceiver != address(0)) {
                uint256 feeAmount = claimedBalances[i] * feePercentage / BalancerConstants.VAULT_PERCENT_BASIS;
                // @audit doesn't the claimedBalance need to decrease by the feeAmount?
                // @audit-ok claimedBalances is only used for return values, but that should be noted here
                // or we make this internal and enforce it. We don't want to run into a situation where
                // the return value is used later and it is inaccurate.
                context.rewardTokens[i].checkTransfer(feeReceiver, feeAmount);
            }
        }
    }
}
