// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {DeploymentParams} from "./BalancerVaultTypes.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";

// @audit this should be called BalancerStrategyStorage
abstract contract BaseVaultStorage is BaseStrategyVault {

    /** Immutables */
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;

    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        BaseStrategyVault(notional_, params.tradingModule)
    {
        SETTLEMENT_PERIOD_IN_SECONDS = params.settlementPeriodInSeconds;
    }

    function _revertInSettlementWindow(uint256 maturity) internal view {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert();
        }
    }
    
    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}