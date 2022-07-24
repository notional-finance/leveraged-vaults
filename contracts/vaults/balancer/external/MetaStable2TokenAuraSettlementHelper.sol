// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    MetaStable2TokenAuraStrategyContext,
    TwoTokenAuraSettlementContext,
    StrategyContext
} from "../BalancerVaultTypes.sol";
import {SettlementHelper} from "../internal/SettlementHelper.sol";

library MetaStable2TokenAuraSettlementHelper {
    function settleVaultNormal(
        MetaStable2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementHelper._settleVaultNormal({
            context: TwoTokenAuraSettlementContext({
                strategyContext: context.baseContext,
                oracleContext: context.oracleContext.baseContext,
                poolContext: context.poolContext,
                stakingContext: context.stakingContext
            }),
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            data: data
        });
    }

    function settleVaultPostMaturity(
        MetaStable2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementHelper._settleVaultPostMaturity({
            context: TwoTokenAuraSettlementContext({
                strategyContext: context.baseContext,
                oracleContext: context.oracleContext.baseContext,
                poolContext: context.poolContext,
                stakingContext: context.stakingContext
            }),
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            data: data
        });    
    }

    function settleVaultEmergency(
        MetaStable2TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        SettlementHelper._settleVaultEmergency({
            context: TwoTokenAuraSettlementContext({
                strategyContext: context.baseContext,
                oracleContext: context.oracleContext.baseContext,
                poolContext: context.poolContext,
                stakingContext: context.stakingContext
            }),
            maturity: maturity,
            data: data
        });
    }
}
