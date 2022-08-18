// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    SingleSidedRewardTradeParams,
    ReinvestRewardParams,
    ThreeTokenPoolContext,
    AuraStakingContext,
    BoostedOracleContext
} from "../../BalancerVaultTypes.sol";
import {Events} from "../../../../global/Events.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {StableMath} from "../math/StableMath.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";
import {IBoostedPool} from "../../../../../interfaces/balancer/IBalancerPool.sol";

library Boosted3TokenAuraRewardUtils {
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;

    function _validateTrade(
        AuraStakingContext memory context,
        SingleSidedRewardTradeParams memory params,
        address primaryToken
    ) private view {
        // Validate trades
        if (!context._isValidRewardToken(params.sellToken)) {
            revert Errors.InvalidRewardToken(params.sellToken);
        }
        if (params.buyToken != IBoostedPool(primaryToken).getMainToken()) {
            revert Errors.InvalidRewardToken(params.buyToken);
        }

        require(params.tradeParams.oracleSlippagePercent <= Constants.MAX_REWARD_TRADE_SLIPPAGE_PERCENT);
    }

    function _executeRewardTrades(
        ThreeTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        bytes memory data
    ) private returns (address rewardToken, uint256 primaryAmount) {
        SingleSidedRewardTradeParams memory params = abi.decode(
            data,
            (SingleSidedRewardTradeParams)
        );

        _validateTrade(stakingContext, params, poolContext.basePool.primaryToken);

        (/*uint256 amountSold*/, primaryAmount) = StrategyUtils._executeDynamicTradeExactIn({
            params: params.tradeParams,
            tradingModule: tradingModule,
            sellToken: params.sellToken,
            buyToken: params.buyToken,
            amount: params.amount
        });

        rewardToken = params.sellToken;
    }

    function _reinvestReward(
        ThreeTokenPoolContext memory poolContext,
        BoostedOracleContext memory oracleContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        ReinvestRewardParams memory params
    ) internal {
        (address rewardToken, uint256 primaryAmount) = _executeRewardTrades(
            poolContext,
            stakingContext,
            tradingModule,
            params.tradeData
        );

        // Calculate minBPT to minimize slippage
        (
           uint256 virtualSupply, 
           uint256[] memory balances, 
           uint256 invariant
        ) = poolContext._getValidatedPoolData(
            oracleContext, tradingModule
        );

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[0] = primaryAmount;

        uint256 minBPT = StableMath._calcBptOutGivenExactTokensIn({
            amp: oracleContext.ampParam,
            balances: balances,
            amountsIn: amountsIn,
            bptTotalSupply: virtualSupply,
            swapFeePercentage: 0,
            currentInvariant: invariant
        });

        minBPT = minBPT * Constants.MAX_BOOSTED_POOL_SLIPPAGE_PERCENT / 
            uint256(Constants.PERCENTAGE_DECIMALS);

        uint256 bptAmount = poolContext._joinPoolExactTokensIn(primaryAmount, minBPT);

        stakingContext.auraBooster.deposit(
            stakingContext.auraPoolId, bptAmount, true // stake = true
        );

        emit Events.RewardReinvested(rewardToken, primaryAmount, 0, bptAmount); 
    }  
}