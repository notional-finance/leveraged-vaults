// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import "./BalancerVaultStorage.sol";

abstract contract Weighted2TokenVaultStorage is BalancerVaultStorage {
    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        BalancerVaultStorage(notional_, params) {

    }
}
