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
        Boosted3TokenAuraStrategyContext calldata context,
        ReinvestRewardParams calldata params
    ) external {        
        context.poolContext._reinvestReward({
            oracleContext: context.oracleContext,
            stakingContext: context.stakingContext,
            tradingModule: context.baseStrategy.tradingModule,
            params: params
        });
    }
}
