// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../../../interfaces/IERC20.sol";

library RewardUtils {
    function _isValidRewardToken(IERC20[] memory rewardTokens, address token)
        internal pure returns (bool) {
        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            if (address(rewardTokens[i]) == token) return true;
        }
        return false;
    }
}
