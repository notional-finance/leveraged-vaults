// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {MetaStable2TokenAuraStrategyContext} from "../BalancerVaultTypes.sol";

library MetaStable2TokenAuraVaultHelper {
    function _depositFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 strategyTokensMinted) {
    
    }

    function _redeemFromNotional(
        MetaStable2TokenAuraStrategyContext memory context,
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) external returns (uint256 finalPrimaryBalance) {
    
    }
}
