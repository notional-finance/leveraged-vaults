// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    Weighted2TokenAuraStrategyContext, 
    TwoTokenAuraSettlementContext,
    StrategyContext
} from "../BalancerVaultTypes.sol";
import {SettlementHelper} from "../internal/SettlementHelper.sol";

library Weighted2TokenAuraSettlementHelper {
    function settleVaultNormal(
        Weighted2TokenAuraStrategyContext memory context,
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
        Weighted2TokenAuraStrategyContext memory context,
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
        Weighted2TokenAuraStrategyContext memory context, 
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
