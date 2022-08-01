// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    Boosted3TokenAuraStrategyContext,
    StableOracleContext
} from "../BalancerVaultTypes.sol";
import {Boosted3TokenAuraRewardUtils} from "../internal/Boosted3TokenAuraRewardUtils.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Stable2TokenOracleMath} from "../internal/Stable2TokenOracleMath.sol";

library Boosted3TokenAuraRewardHelper {
    using Stable2TokenOracleMath for StableOracleContext;

    function reinvestReward(
        Boosted3TokenAuraStrategyContext memory context,
        ReinvestRewardParams memory params
    ) external {
        Boosted3TokenAuraRewardUtils._reinvestReward({
            poolContext: context.poolContext,
            stakingContext: context.stakingContext,
            tradingModule: context.baseStrategy.tradingModule,
            params: params
        });
    }
}
