// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {AuraStakingContext, PoolContext, PoolParams} from "../../BalancerVaultTypes.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";

library AuraStakingUtils {
    function _isValidRewardToken(AuraStakingContext memory context, address token)
        internal pure returns (bool) {
        // @audit cache array length
        for (uint256 i; i < context.rewardTokens.length; i++) {
            if (address(context.rewardTokens[i]) == token) return true;
        }
        return false;
    }
}
