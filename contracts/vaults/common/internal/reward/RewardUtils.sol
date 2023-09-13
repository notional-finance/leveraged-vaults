// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Deployments} from "../../../../global/Deployments.sol";
import {Constants} from "../../../../global/Constants.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";
import {IConvexRewardPool, IConvexRewardPoolArbitrum} from "../../../../../interfaces/convex/IConvexRewardPool.sol";
import {VaultEvents} from "../../VaultEvents.sol";

library RewardUtils {
    function _isValidRewardToken(IERC20[] memory rewardTokens, address token)
        internal pure returns (bool) {
        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            if (address(rewardTokens[i]) == token) return true;
        }
        return false;
    }

    function _claimRewardTokens(function() internal returns(bool) claimFunc, IERC20[] memory rewardTokens) 
        internal returns (uint256[] memory claimedBalances) {
        uint256 numRewardTokens = rewardTokens.length;

        claimedBalances = new uint256[](numRewardTokens);
        for (uint256 i; i < numRewardTokens; i++) {
            claimedBalances[i] = rewardTokens[i].balanceOf(address(this));
        }

        bool success = claimFunc();
        require(success);

        for (uint256 i; i < numRewardTokens; i++) {
            claimedBalances[i] = rewardTokens[i].balanceOf(address(this)) - claimedBalances[i];
        }
        
        emit VaultEvents.ClaimedRewardTokens(rewardTokens, claimedBalances);
    }
}
