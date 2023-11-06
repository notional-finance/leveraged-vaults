
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    SingleSidedRewardTradeParams,
    StrategyContext,
    ComposableRewardTradeParams
} from "../../../common/VaultTypes.sol";
import {BalancerComposablePoolContext, AuraStakingContext} from "../../BalancerVaultTypes.sol";
import {Errors} from "../../../../global/Errors.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {
    ReinvestRewardParams
} from "../../../../../interfaces/notional/ISingleSidedLPStrategyVault.sol";

/**
 * Utility functions for Aura rewards
 */
library ComposableAuraRewardUtils {
    using StrategyUtils for StrategyContext;

    /// @notice Validate reward trade to make sure the core tokens are not being sold
    /// @param poolTokens list of pool tokens
    /// @param params single-sided trade params
    /// @param stakedPoolToken Aura staked pool token
    /// @param token one of the whitelisted tokens that the vault can buy
    function _validateTrade(
        address[] memory poolTokens,
        SingleSidedRewardTradeParams memory params,
        address stakedPoolToken,
        address token
    ) private pure {
        // Make sure we are not selling the Aura staked BPT
        if (params.sellToken == stakedPoolToken) {
            revert Errors.InvalidRewardToken(params.sellToken);
        }
        // Make sure we are not selling one of the pool tokens
        for (uint256 i; i < poolTokens.length; i++) {
            if (params.sellToken == poolTokens[i]) {
                revert Errors.InvalidRewardToken(params.sellToken);
            }
        }
        // Vault can only buy whitelisted tokens
        if (params.buyToken != token) {
            revert Errors.InvalidRewardToken(params.buyToken);
        }
    }

    /// @notice internal function to avoid stack issues
    /// @param strategyContext strategy context
    /// @param params single-sided trade params
    /// @return amountSold amount of tokens sold
    /// @return amountBought amount of tokens bought
    function _executeTrade(StrategyContext memory strategyContext, SingleSidedRewardTradeParams memory params)
        private returns (uint256, uint256) {
        return strategyContext._executeTradeExactIn(
            params.tradeParams, params.sellToken, params.buyToken, params.amount, false // useDynamicSlippage
        );
    }

    /// @notice execute reward trades
    /// @param poolContext pool context
    /// @param strategyContext strategy context
    /// @param stakingContext staking context
    /// @param data ABI encoded trade params
    /// @return rewardToken reward token address
    /// @return amountSold amount of tokens sold
    /// @return amounts amounts of tokens bought
    function _executeRewardTrades(
        BalancerComposablePoolContext calldata poolContext,
        StrategyContext memory strategyContext,
        AuraStakingContext calldata stakingContext,
        bytes calldata data
    ) internal returns (address rewardToken, uint256 amountSold, uint256[] memory amounts) {
        // Decode trade params
        ComposableRewardTradeParams memory params = abi.decode(data, (ComposableRewardTradeParams));

        uint256 numTokens = poolContext.basePool.tokens.length;
        amounts = new uint256[](numTokens);

        // Trade index doesn't include the BPT index
        // the length of the rewardTrades array should be 1 less than the 
        // length of the pool
        uint256 tradeIndex;
        for (uint256 i; i < numTokens; i++) {
            // Skip pool token
            if (i == poolContext.bptIndex) continue;

            // All reward trades should have the same sell token
            if (rewardToken == address(0)) {
                rewardToken = params.rewardTrades[tradeIndex].sellToken;
            } else {
                require(params.rewardTrades[tradeIndex].sellToken == rewardToken);
            }

            _validateTrade(
                poolContext.basePool.tokens, 
                params.rewardTrades[tradeIndex], 
                poolContext.basePool.tokens[i],
                address(stakingContext.rewardPool)
            );

            (amountSold, amounts[i]) = _executeTrade(strategyContext, params.rewardTrades[tradeIndex]);
            
            tradeIndex++;
        }
    }
}
