// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    Boosted3TokenAuraStrategyContext,
    StableOracleContext,
    ThreeTokenPoolContext
} from "../BalancerVaultTypes.sol";
import {Boosted3TokenAuraRewardUtils} from "../internal/reward/Boosted3TokenAuraRewardUtils.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Stable2TokenOracleMath} from "../internal/math/Stable2TokenOracleMath.sol";

library Boosted3TokenAuraRewardHelper {
    using Stable2TokenOracleMath for StableOracleContext;
    using Boosted3TokenAuraRewardUtils for ThreeTokenPoolContext;

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
}
