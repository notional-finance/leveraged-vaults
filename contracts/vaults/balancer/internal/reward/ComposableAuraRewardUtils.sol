
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

/**
 * Utility functions for Aura rewards
 */
library ComposableAuraRewardUtils {

    // function _validateTrade(
    //     address[] memory poolTokens,
    //     SingleSidedRewardTradeParams memory params,
    //     address stakedPoolToken,
    //     address token
    // ) private pure {
    //     // Make sure we are not selling the Aura staked BPT
    //     if (params.sellToken == stakedPoolToken) {
    //         revert Errors.InvalidRewardToken(params.sellToken);
    //     }
    //     // Make sure we are not selling one of the pool tokens
    //     for (uint256 i; i < poolTokens.length; i++) {
    //         if (params.sellToken == poolTokens[i]) {
    //             revert Errors.InvalidRewardToken(params.sellToken);
    //         }
    //     }
    //     // Vault can only buy whitelisted tokens
    //     if (params.buyToken != token) {
    //         revert Errors.InvalidRewardToken(params.buyToken);
    //     }
    // }
}
