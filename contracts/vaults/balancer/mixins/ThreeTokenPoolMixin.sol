// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {Constants} from "../../../global/Constants.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {ThreeTokenPoolContext} from "../BalancerVaultTypes.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {TwoTokenPoolMixin} from "./TwoTokenPoolMixin.sol";

abstract contract ThreeTokenPoolMixin is TwoTokenPoolMixin {
    IERC20 internal immutable TERTIARY_TOKEN;
    uint8 internal immutable TERTIARY_INDEX;
    uint8 internal immutable TERTIARY_DECIMALS;

    constructor(
        uint16 primaryBorrowCurrencyId, 
        bytes32 balancerPoolId, 
        uint16 secondaryBorrowCurrencyId
    ) TwoTokenPoolMixin(primaryBorrowCurrencyId, balancerPoolId, secondaryBorrowCurrencyId) {
        unchecked {
            TERTIARY_INDEX = 2 - (PRIMARY_INDEX - SECONDARY_INDEX);
        }

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(balancerPoolId);

        TERTIARY_TOKEN = IERC20(tokens[TERTIARY_INDEX]);

        address tertiaryAddress = BalancerUtils.getTokenAddress(address(TERTIARY_TOKEN));
        
        // If the underlying is ETH, primaryBorrowToken will be rewritten as WETH
        uint256 tertiaryDecimals = IERC20(tertiaryAddress).decimals();
        // Do not allow decimal places greater than 18
        require(tertiaryDecimals <= 18);
        TERTIARY_DECIMALS = uint8(tertiaryDecimals);        
    }

    function _threeTokenPoolContext() internal view returns (ThreeTokenPoolContext memory) {
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        return ThreeTokenPoolContext({
            tertiaryToken: address(TERTIARY_TOKEN),
            tertiaryIndex: TERTIARY_INDEX,
            tertiaryDecimals: TERTIARY_DECIMALS,
            tertiaryBalance: balances[TERTIARY_INDEX],
            basePool: _twoTokenPoolContext()
        });
    }
}
