// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {TwoTokenPoolContext} from "../../common/VaultTypes.sol";
import {Balancer2TokenPoolContext, AuraVaultDeploymentParams} from "../BalancerVaultTypes.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {BalancerPoolMixin} from "./BalancerPoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IBalancerPool} from "../../../../interfaces/balancer/IBalancerPool.sol";

abstract contract Balancer2TokenPoolMixin is BalancerPoolMixin {
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
        AuraVaultDeploymentParams memory params
    ) BalancerPoolMixin(notional_, params) {
        PRIMARY_TOKEN = _getNotionalUnderlyingToken(params.baseParams.primaryBorrowCurrencyId);
        address primaryAddress = BalancerUtils.getTokenAddress(PRIMARY_TOKEN);

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(params.baseParams.balancerPoolId);

        // Balancer tokens are sorted by address, so we need to figure out
        // the correct index for the primary token
        PRIMARY_INDEX = tokens[0] == primaryAddress ? 0 : 1;
        unchecked {
            SECONDARY_INDEX = 1 - PRIMARY_INDEX;
        }

        SECONDARY_TOKEN = tokens[SECONDARY_INDEX];

        // Make sure the deployment parameters are correct
        if (tokens[PRIMARY_INDEX] != primaryAddress) {
            revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        }

        if (tokens[SECONDARY_INDEX] !=
            BalancerUtils.getTokenAddress(SECONDARY_TOKEN)
        ) revert InvalidSecondaryToken(tokens[SECONDARY_INDEX]);

        // If the underlying is ETH, primaryBorrowToken will be rewritten as WETH
        uint256 primaryDecimals = IERC20(primaryAddress).decimals();
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

    function _twoTokenPoolContext() internal view returns (Balancer2TokenPoolContext memory) {
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        uint256[] memory scalingFactors = IBalancerPool(address(BALANCER_POOL_TOKEN)).getScalingFactors();

        return Balancer2TokenPoolContext({
            basePool: TwoTokenPoolContext({
                primaryToken: PRIMARY_TOKEN,
                secondaryToken: SECONDARY_TOKEN,
                primaryIndex: PRIMARY_INDEX,
                secondaryIndex: SECONDARY_INDEX,
                primaryDecimals: PRIMARY_DECIMALS,
                secondaryDecimals: SECONDARY_DECIMALS,
                primaryBalance: balances[PRIMARY_INDEX],
                secondaryBalance: balances[SECONDARY_INDEX],
                poolToken: BALANCER_POOL_TOKEN
            }),
            primaryScaleFactor: scalingFactors[PRIMARY_INDEX],
            secondaryScaleFactor: scalingFactors[SECONDARY_INDEX],
            poolId: BALANCER_POOL_ID
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
