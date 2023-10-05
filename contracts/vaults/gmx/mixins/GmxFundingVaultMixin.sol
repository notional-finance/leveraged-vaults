// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Deployments} from "../../../global/Deployments.sol";
import {DeploymentParams} from "../GmxVaultTypes.sol";
import {VaultBase} from "../../common/VaultBase.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IGmxExchangeRouter} from "../../../../interfaces/gmx/IGmxExchangeRouter.sol";
import {IGmxReader} from "../../../../interfaces/gmx/IGmxReader.sol";
import {IERC20} from "../../../utils/TokenUtils.sol";

abstract contract GmxFundingVaultMixin is VaultBase {
    address internal immutable PRIMARY_TOKEN;
    uint256 internal immutable PRIMARY_PRECISION;
    address internal immutable COLLATERAL_TOKEN;
    uint256 internal immutable COLLATERAL_PRECISION;
    IGmxExchangeRouter internal immutable GMX_ROUTER;
    address internal immutable GMX_SPENDER;
    address internal immutable GMX_MARKET;
    address internal immutable GMX_DATASTORE;
    IGmxReader internal immutable GMX_READER;
    address internal immutable ORDER_VAULT;

    constructor(
        NotionalProxy notional_,
        DeploymentParams memory params
    ) VaultBase(notional_, params.tradingModule) {
        PRIMARY_TOKEN = _getNotionalUnderlyingToken(params.primaryBorrowCurrencyId);

        COLLATERAL_TOKEN = params.collateralToken;
        GMX_ROUTER = IGmxExchangeRouter(params.gmxRouter);

        GMX_DATASTORE = GMX_ROUTER.dataStore();
        GMX_SPENDER = GMX_ROUTER.router();

        GMX_MARKET = params.gmxMarket;
        GMX_READER = IGmxReader(params.gmxReader);
        ORDER_VAULT = params.orderVault;

        PRIMARY_PRECISION = PRIMARY_TOKEN == Deployments.ETH_ADDRESS
            ? 1e18
            : 10 ** IERC20(PRIMARY_TOKEN).decimals();
        require(PRIMARY_PRECISION <= 1e18);

        COLLATERAL_PRECISION = COLLATERAL_TOKEN == Deployments.ETH_ADDRESS
            ? 1e18
            : 10 ** IERC20(COLLATERAL_TOKEN).decimals();
        require(COLLATERAL_PRECISION <= 1e18);
    }
}
