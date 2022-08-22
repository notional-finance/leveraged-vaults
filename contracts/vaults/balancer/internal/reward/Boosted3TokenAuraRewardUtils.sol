// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    SingleSidedRewardTradeParams,
    ReinvestRewardParams,
    ThreeTokenPoolContext,
    AuraStakingContext,
    BoostedOracleContext
} from "../../BalancerVaultTypes.sol";
import {BalancerEvents} from "../../BalancerEvents.sol";
import {Errors} from "../../../../global/Errors.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
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
        AuraStakingContext calldata context,
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

        require(params.tradeParams.oracleSlippagePercent <= BalancerConstants.MAX_REWARD_TRADE_SLIPPAGE_PERCENT);
    }

    function _executeRewardTrades(
        ThreeTokenPoolContext calldata poolContext,
        AuraStakingContext calldata stakingContext,
        ITradingModule tradingModule,
        bytes calldata data
    ) private returns (address rewardToken, uint256 primaryAmount) {
        SingleSidedRewardTradeParams memory params = abi.decode(data, (SingleSidedRewardTradeParams));

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
        ThreeTokenPoolContext calldata poolContext,
        BoostedOracleContext calldata oracleContext,
        AuraStakingContext calldata stakingContext,
        ITradingModule tradingModule,
        ReinvestRewardParams calldata params
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
        ) = poolContext._getValidatedPoolData(oracleContext, tradingModule);

        uint256[] memory amountsIn = new uint256[](3);
        // _getValidatedPoolData rearranges the balances so that primary is always in the
        // zero index spot
        amountsIn[0] = primaryAmount;

        uint256 minBPT = StableMath._calcBptOutGivenExactTokensIn({
            amp: oracleContext.ampParam,
            balances: balances,
            amountsIn: amountsIn,
            bptTotalSupply: virtualSupply,
            swapFeePercentage: 0,
            currentInvariant: invariant
        });

        minBPT = minBPT * BalancerConstants.MAX_BOOSTED_POOL_SLIPPAGE_PERCENT / 
            // @audit is this the right decimals?
            uint256(BalancerConstants.PERCENTAGE_DECIMALS);

        uint256 bptAmount = poolContext._joinPoolExactTokensIn(primaryAmount, minBPT);

        stakingContext.auraBooster.deposit(
            stakingContext.auraPoolId, bptAmount, true // stake = true
        );

        // @audit we miss the threshold check here as well

        emit BalancerEvents.RewardReinvested(rewardToken, primaryAmount, 0, bptAmount); 
    }  
}