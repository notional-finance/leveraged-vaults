// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {AuraVaultDeploymentParams} from "../vaults/balancer/BalancerVaultTypes.sol";
import {MetaStable2TokenAuraVault} from "../vaults/MetaStable2TokenAuraVault.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";

contract MockMetaStable2TokenAuraVault is MetaStable2TokenAuraVault {
    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params
    ) MetaStable2TokenAuraVault(notional_, params) {
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        return super.convertStrategyToUnderlying(account, strategyTokenAmount, maturity);
    }
}
