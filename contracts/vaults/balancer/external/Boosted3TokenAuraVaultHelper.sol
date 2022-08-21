// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext,
    DepositParams,
    RedeemParams,
    ReinvestRewardParams,
    StrategyContext,
    ThreeTokenPoolContext
} from "../BalancerVaultTypes.sol";
import {Boosted3TokenAuraStrategyUtils} from "../internal/strategy/Boosted3TokenAuraStrategyUtils.sol";
import {Boosted3TokenAuraRewardUtils} from "../internal/reward/Boosted3TokenAuraRewardUtils.sol";

library Boosted3TokenAuraVaultHelper {
    using Boosted3TokenAuraRewardUtils for ThreeTokenPoolContext;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;

    function reinvestReward(
        Boosted3TokenAuraStrategyContext memory context,
        ReinvestRewardParams memory params
    ) external {        
        context.poolContext._reinvestReward({
            oracleContext: context.oracleContext,
            stakingContext: context.stakingContext,
            tradingModule: context.baseStrategy.tradingModule,
            params: params
        });
    }

    function depositFromNotional(
        // @audit switch to calldata
        Boosted3TokenAuraStrategyContext memory context,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));
        strategyTokensMinted = context.baseStrategy._deposit({
            stakingContext: context.stakingContext, 
            poolContext: context.poolContext,
            deposit: deposit,
            minBPT: params.minBPT
        });
    }

    function redeemFromNotional(
        // @audit switch to calldata
        Boosted3TokenAuraStrategyContext memory context,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        finalPrimaryBalance = context.baseStrategy._redeem({
            stakingContext: context.stakingContext,
            poolContext: context.poolContext,
            strategyTokens: strategyTokens,
            minPrimary: params.minPrimary
        });
    }
}
