// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {TwoTokenPoolContext} from "../../common/VaultTypes.sol";
import {Curve2TokenPoolContext, ConvexVaultDeploymentParams} from "../CurveVaultTypes.sol";
import {CurveConstants} from "../internal/CurveConstants.sol";
import {CurvePoolMixin} from "./CurvePoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IBalancerPool} from "../../../../interfaces/balancer/IBalancerPool.sol";

abstract contract Curve2TokenPoolMixin is CurvePoolMixin {
    error InvalidPrimaryToken(address token);
    error InvalidSecondaryToken(address token);

    address internal immutable PRIMARY_TOKEN;
    address internal immutable SECONDARY_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;
    uint8 internal immutable SECONDARY_INDEX;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;

    constructor(
        NotionalProxy notional_,
        ConvexVaultDeploymentParams memory params
    ) CurvePoolMixin(notional_, params) {
        address primaryToken = _getNotionalUnderlyingToken(params.baseParams.primaryBorrowCurrencyId);

        PRIMARY_TOKEN = primaryToken;

        // Curve uses ALT_ETH_ADDRESS
        if (primaryToken == Deployments.ETH_ADDRESS) {
            primaryToken = Deployments.ALT_ETH_ADDRESS;
        }

        address token0 = CURVE_POOL.coins(0);
        address token1 = CURVE_POOL.coins(1);
        
        uint8 primaryIndex;
        address secondaryToken;
        if (token0 == primaryToken) {
            primaryIndex = 0;
            secondaryToken = token1;
        } else {
            primaryIndex = 1;
            secondaryToken = token0;
        }

        if (secondaryToken == Deployments.ALT_ETH_ADDRESS) {
            secondaryToken = Deployments.ETH_ADDRESS;
        }

        PRIMARY_INDEX = primaryIndex;
        SECONDARY_TOKEN = secondaryToken;

        unchecked {
            SECONDARY_INDEX = 1 - PRIMARY_INDEX;
        }

        uint256 primaryDecimals = PRIMARY_TOKEN ==
            Deployments.ETH_ADDRESS
            ? 18
            : IERC20(PRIMARY_TOKEN).decimals();
        // Do not allow decimal places greater than 18
        require(primaryDecimals <= 18);
        PRIMARY_DECIMALS = uint8(primaryDecimals);

        uint256 secondaryDecimals = SECONDARY_TOKEN ==
            Deployments.ETH_ADDRESS
            ? 18
            : IERC20(SECONDARY_TOKEN).decimals();
        require(secondaryDecimals <= 18);
        SECONDARY_DECIMALS = uint8(secondaryDecimals);
    }

    function _twoTokenPoolContext() internal view returns (Curve2TokenPoolContext memory) {
        return Curve2TokenPoolContext({
            basePool: TwoTokenPoolContext({
                primaryToken: PRIMARY_TOKEN,
                secondaryToken: SECONDARY_TOKEN,
                primaryIndex: PRIMARY_INDEX,
                secondaryIndex: SECONDARY_INDEX,
                primaryDecimals: PRIMARY_DECIMALS,
                secondaryDecimals: SECONDARY_DECIMALS,
                primaryBalance: CURVE_POOL.balances(PRIMARY_INDEX),
                secondaryBalance: CURVE_POOL.balances(SECONDARY_INDEX),
                poolToken: CURVE_POOL_TOKEN      
            }),
            curvePool: CURVE_POOL
        });   
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
