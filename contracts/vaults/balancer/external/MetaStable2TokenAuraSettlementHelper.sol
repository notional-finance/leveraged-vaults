// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {MetaStable2TokenAuraStrategyContext} from "../BalancerVaultTypes.sol";

library MetaStable2TokenAuraSettlementHelper {
    function settleVaultNormal(
        MetaStable2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {

    }

    function settleVaultPostMaturity(
        MetaStable2TokenAuraStrategyContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
    
    }

    function settleVaultEmergency(
        MetaStable2TokenAuraStrategyContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {

    }
}
