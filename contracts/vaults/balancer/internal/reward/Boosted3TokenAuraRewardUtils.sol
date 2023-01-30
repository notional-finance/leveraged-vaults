// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    SingleSidedRewardTradeParams,
    AuraStakingContext,
    BoostedOracleContext
} from "../../BalancerVaultTypes.sol";
import {ThreeTokenPoolContext,  ReinvestRewardParams} from "../../../common/VaultTypes.sol";
import {BalancerEvents} from "../../BalancerEvents.sol";
import {Errors} from "../../../../global/Errors.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Balancer3TokenBoostedPoolUtils} from "../pool/Balancer3TokenBoostedPoolUtils.sol";
import {StrategyUtils} from "../../../common/internal/strategy/StrategyUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";
import {ILinearPool} from "../../../../../interfaces/balancer/IBalancerPool.sol";

library Boosted3TokenAuraRewardUtils {
    using AuraStakingUtils for AuraStakingContext;

    function _validateTrade(
        AuraStakingContext calldata context,
        SingleSidedRewardTradeParams memory params,
        address primaryToken
    ) private view {
        // Validate trades
        if (!context._isValidRewardToken(params.sellToken)) {
            revert Errors.InvalidRewardToken(params.sellToken);
        }
        if (params.buyToken != ILinearPool(primaryToken).getMainToken()) {
            revert Errors.InvalidRewardToken(params.buyToken);
        }
    }

    function _executeRewardTrades(
        ThreeTokenPoolContext calldata poolContext,
        AuraStakingContext calldata stakingContext,
        ITradingModule tradingModule,
        bytes calldata data
    ) internal returns (address rewardToken, uint256 primaryAmount) {
        SingleSidedRewardTradeParams memory params = abi.decode(data, (SingleSidedRewardTradeParams));

        _validateTrade(stakingContext, params, poolContext.basePool.primaryToken);

        (/*uint256 amountSold*/, primaryAmount) = StrategyUtils._executeTradeExactIn({
            params: params.tradeParams,
            tradingModule: tradingModule,
            sellToken: params.sellToken,
            buyToken: params.buyToken,
            amount: params.amount,
            useDynamicSlippage: false
        });

        rewardToken = params.sellToken;
    }
}