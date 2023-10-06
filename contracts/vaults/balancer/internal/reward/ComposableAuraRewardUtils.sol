
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ReinvestRewardParams, 
    SingleSidedRewardTradeParams,
    StrategyContext,
    ComposableRewardTradeParams
} from "../../../common/VaultTypes.sol";
import {BalancerComposablePoolContext} from "../../BalancerVaultTypes.sol";
import {VaultEvents} from "../../../common/VaultEvents.sol";
import {Errors} from "../../../../global/Errors.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";

library ComposableAuraRewardUtils {
    using StrategyUtils for StrategyContext;

    function _validateTrade(
        address[] memory poolTokens,
        SingleSidedRewardTradeParams memory params,
        address token
    ) private view {
        // Make sure we are not selling one of the core tokens
        for (uint256 i; i < poolTokens.length; i++) {
            if (params.sellToken == poolTokens[i]) {
                revert Errors.InvalidRewardToken(params.sellToken);
            }            
        }
        if (params.buyToken != token) {
            revert Errors.InvalidRewardToken(params.buyToken);
        }
    }

    function _executeTrade(
        StrategyContext memory strategyContext, 
        SingleSidedRewardTradeParams memory params
    ) private returns (uint256, uint256) {
        return strategyContext._executeTradeExactIn({
            params: params.tradeParams,
            sellToken: params.sellToken,
            buyToken: params.buyToken,
            amount: params.amount,
            useDynamicSlippage: false
        });        
    }

    function _executeRewardTrades(
        BalancerComposablePoolContext calldata poolContext,
        StrategyContext memory strategyContext,
        bytes calldata data
    ) internal returns (address rewardToken, uint256 amountSold, uint256[] memory amounts) {
        ComposableRewardTradeParams memory params = abi.decode(
            data,
            (ComposableRewardTradeParams)
        );

        uint256 numTokens = poolContext.basePool.tokens.length;
        amounts = new uint256[](numTokens);

        uint256 tradeIndex;
        for (uint256 i; i < numTokens; i++) {
            if (i == poolContext.bptIndex) continue;

            _validateTrade(poolContext.basePool.tokens, params.rewardTrades[tradeIndex], poolContext.basePool.tokens[i]);

            (amountSold, amounts[i]) = _executeTrade(strategyContext, params.rewardTrades[tradeIndex]);
            
            tradeIndex++;
        }

        rewardToken = params.rewardTrades[0].sellToken;
    }
}
