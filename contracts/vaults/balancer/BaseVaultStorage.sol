// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Constants} from "../../global/Constants.sol";
import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {
    DeploymentParams,
    InitParams,
    StrategyVaultSettings,
    StrategyVaultState,
    SettlementState,
    PoolContext,
    OracleContext
} from "./BalancerVaultTypes.sol";
import {Token} from "../../global/Types.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";

abstract contract BaseVaultStorage is BaseStrategyVault {

    /** Immutables */
    uint16 internal immutable SECONDARY_BORROW_CURRENCY_ID;
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;
    address internal immutable FEE_RECEIVER;

    constructor(NotionalProxy notional_, DeploymentParams memory params) 
        BaseStrategyVault(notional_, params.tradingModule)
    {
        SECONDARY_BORROW_CURRENCY_ID = params.secondaryBorrowCurrencyId;
        SETTLEMENT_PERIOD_IN_SECONDS = params.settlementPeriodInSeconds;
        FEE_RECEIVER = params.feeReceiver;
    }

    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}