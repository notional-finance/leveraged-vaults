// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {Constants} from "../../../global/Constants.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {TwoTokenPoolContext} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "../BalancerUtils.sol";
import {PoolMixin} from "./PoolMixin.sol";

abstract contract TwoTokenPoolMixin is PoolMixin {
    error InvalidPrimaryToken(address token);
    error InvalidSecondaryToken(address token);

    uint16 internal immutable SECONDARY_BORROW_CURRENCY_ID;
    IERC20 internal immutable PRIMARY_TOKEN;
    IERC20 internal immutable SECONDARY_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;

    constructor(
        uint16 primaryBorrowCurrencyId, 
        bytes32 balancerPoolId, 
        uint16 secondaryBorrowCurrencyId
    ) PoolMixin(balancerPoolId) {
        SECONDARY_BORROW_CURRENCY_ID = secondaryBorrowCurrencyId;
        PRIMARY_TOKEN = IERC20(NotionalUtils._getNotionalUnderlyingToken(primaryBorrowCurrencyId));
        address primaryAddress = BalancerUtils.getTokenAddress(address(PRIMARY_TOKEN));

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(balancerPoolId);

        // Balancer tokens are sorted by address, so we need to figure out
        // the correct index for the primary token
        PRIMARY_INDEX = tokens[0] == primaryAddress ? 0 : 1;
        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - PRIMARY_INDEX;
        }

        // Since this is always a 2-token vault, SECONDARY_INDEX = 1-PRIMARY_INDEX
        SECONDARY_TOKEN = secondaryBorrowCurrencyId > 0
            ? IERC20(NotionalUtils._getNotionalUnderlyingToken(secondaryBorrowCurrencyId))
            : IERC20(tokens[secondaryIndex]);

        // Make sure the deployment parameters are correct
        if (tokens[PRIMARY_INDEX] != primaryAddress) {
            revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        }

        if (tokens[secondaryIndex] !=
            BalancerUtils.getTokenAddress(address(SECONDARY_TOKEN))
        ) revert InvalidSecondaryToken(tokens[secondaryIndex]);

        // If the underlying is ETH, primaryBorrowToken will be rewritten as WETH
        uint256 primaryDecimals = IERC20(primaryAddress).decimals();
        // Do not allow decimal places greater than 18
        require(primaryDecimals <= 18);
        PRIMARY_DECIMALS = uint8(primaryDecimals);

        uint256 secondaryDecimals = address(SECONDARY_TOKEN) ==
            Constants.ETH_ADDRESS
            ? 18
            : SECONDARY_TOKEN.decimals();
        require(primaryDecimals <= 18);
        SECONDARY_DECIMALS = uint8(secondaryDecimals);
    }

    function _twoTokenPoolContext() internal view returns (TwoTokenPoolContext memory) {
        return TwoTokenPoolContext({
            primaryToken: address(PRIMARY_TOKEN),
            secondaryToken: address(SECONDARY_TOKEN),
            primaryIndex: PRIMARY_INDEX,
            primaryDecimals: PRIMARY_DECIMALS,
            secondaryDecimals: SECONDARY_DECIMALS,
            baseContext: _poolContext()
        });
    }
}
