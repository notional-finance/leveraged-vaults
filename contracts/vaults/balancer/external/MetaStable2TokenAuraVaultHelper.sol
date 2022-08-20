// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams,
    TwoTokenPoolContext,
    StrategyContext,
    StableOracleContext
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/strategy/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenAuraRewardUtils} from "../internal/reward/TwoTokenAuraRewardUtils.sol";
import {Stable2TokenOracleMath} from "../internal/math/Stable2TokenOracleMath.sol";

library MetaStable2TokenAuraVaultHelper {
    using TwoTokenAuraRewardUtils for TwoTokenPoolContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using Stable2TokenOracleMath for StableOracleContext;

    function depositFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        strategyTokensMinted = context.baseStrategy._deposit({
            stakingContext: context.stakingContext, 
            poolContext: context.poolContext,
            deposit: deposit,
            params: params
        });
    }

    function redeemFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        finalPrimaryBalance = context.baseStrategy._redeem({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            account: account,
            strategyTokens: strategyTokens,
            maturity: maturity,
            params: params
        });
    }

    function reinvestReward(
        MetaStable2TokenAuraStrategyContext memory context,
        ReinvestRewardParams memory params
    ) external {
        (
            address rewardToken, 
            uint256 primaryAmount, 
            uint256 secondaryAmount
        ) = context.poolContext._executeRewardTrades(
            context.stakingContext,
            context.baseStrategy.tradingModule,
            params.tradeData
        );

        // Make sure we are joining with the right proportion to minimize slippage
        context.oracleContext._validateSpotPriceAndPairPrice({
            poolContext: context.poolContext,
            tradingModule: context.baseStrategy.tradingModule,
            spotPrice: context.oracleContext._getSpotPrice(context.poolContext, 0),
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });

        context.poolContext._reinvestReward({
            stakingContext: context.stakingContext, 
            params: params,
            rewardToken: rewardToken,
            primaryAmount: primaryAmount,
            secondaryAmount: secondaryAmount
        });
    }
}
