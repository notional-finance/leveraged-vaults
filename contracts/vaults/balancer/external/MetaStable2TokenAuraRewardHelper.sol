// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    MetaStable2TokenAuraStrategyContext,
    StableOracleContext,
    TwoTokenPoolContext
} from "../BalancerVaultTypes.sol";
import {TwoTokenAuraRewardUtils} from "../internal/reward/TwoTokenAuraRewardUtils.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Stable2TokenOracleMath} from "../internal/math/Stable2TokenOracleMath.sol";

library MetaStable2TokenAuraRewardHelper {
    using Stable2TokenOracleMath for StableOracleContext;
    using TwoTokenAuraRewardUtils for TwoTokenPoolContext;

    function reinvestReward(
        MetaStable2TokenAuraStrategyContext memory context,
        ReinvestRewardParams memory params
    ) external {
        context.poolContext._reinvestReward({
            stakingContext: context.stakingContext,
            tradingModule: context.baseStrategy.tradingModule,
            params: params,
            spotPrice: context.oracleContext._getSpotPrice(context.poolContext, 0)
        });
    }
}
