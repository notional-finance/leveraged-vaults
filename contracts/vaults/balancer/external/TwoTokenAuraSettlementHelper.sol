// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {TwoTokenAuraSettlementContext, StrategyContext} from "../BalancerVaultTypes.sol";
import {SettlementHelper} from "../internal/SettlementHelper.sol";

library TwoTokenAuraSettlementHelper {
    using SettlementHelper for TwoTokenAuraSettlementContext;

    function settleVaultNormal(
        TwoTokenAuraSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        context._settleVaultNormal(maturity, strategyTokensToRedeem, data);
    }

    function settleVaultPostMaturity(
        TwoTokenAuraSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        context._settleVaultPostMaturity(maturity, strategyTokensToRedeem, data);  
    }

    function settleVaultEmergency(
        TwoTokenAuraSettlementContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        context._settleVaultEmergency(maturity, data);
    }
}
