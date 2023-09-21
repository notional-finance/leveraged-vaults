// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ThreeTokenPoolContext, 
    ReinvestRewardParams, 
    SingleSidedRewardTradeParams,
    StrategyContext
} from "../../../common/VaultTypes.sol";
import {VaultEvents} from "../../../common/VaultEvents.sol";
import {Errors} from "../../../../global/Errors.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Balancer3TokenBoostedPoolUtils} from "../pool/Balancer3TokenBoostedPoolUtils.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {RewardUtils} from "../../../common/internal/reward/RewardUtils.sol";
import {ILinearPool} from "../../../../../interfaces/balancer/IBalancerPool.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";

library Boosted3TokenAuraRewardUtils {
    using StrategyUtils for StrategyContext;

    function _validateTrade(
        IERC20[] memory rewardTokens,
        SingleSidedRewardTradeParams memory params,
        address primaryToken
    ) private view {
        // Validate trades
        if (!RewardUtils._isValidRewardToken(rewardTokens, params.sellToken)) {
            revert Errors.InvalidRewardToken(params.sellToken);
        }
        if (params.buyToken != ILinearPool(primaryToken).getMainToken()) {
            revert Errors.InvalidRewardToken(params.buyToken);
        }
    }

    function _executeRewardTrades(
        ThreeTokenPoolContext calldata poolContext,
        StrategyContext memory strategyContext,
        IERC20[] memory rewardTokens,
        bytes calldata data
    ) internal returns (address rewardToken, uint256 amountSold, uint256 primaryAmount) {
        SingleSidedRewardTradeParams memory params = abi.decode(data, (SingleSidedRewardTradeParams));

        _validateTrade(rewardTokens, params, poolContext.basePool.primaryToken);

        (amountSold, primaryAmount) = strategyContext._executeTradeExactIn({
            params: params.tradeParams,
            sellToken: params.sellToken,
            buyToken: params.buyToken,
            amount: params.amount,
            useDynamicSlippage: false
        });

        rewardToken = params.sellToken;
    }
}
