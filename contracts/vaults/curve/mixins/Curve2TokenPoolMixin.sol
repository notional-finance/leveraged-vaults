// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {IERC20} from "@interfaces/IERC20.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {
    CurveInterface,
    ICurvePool,
    ICurvePoolV1,
    ICurvePoolV2,
    ICurve2TokenPoolV1,
    ICurve2TokenPoolV2,
    ICurveStableSwapNG
} from "@interfaces/curve/ICurvePool.sol";
import {SingleSidedLPVaultBase} from "@contracts/vaults/common/SingleSidedLPVaultBase.sol";
import {ITradingModule} from "@interfaces/trading/ITradingModule.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    address pool;
    ITradingModule tradingModule;
    address poolToken;
    CurveInterface curveInterface;
}

abstract contract Curve2TokenPoolMixin is SingleSidedLPVaultBase {
    uint256 internal constant _NUM_TOKENS = 2;
    uint256 internal constant CURVE_PRECISION = 1e18;

    address internal immutable CURVE_POOL;
    IERC20 internal immutable CURVE_POOL_TOKEN;
    CurveInterface internal immutable CURVE_INTERFACE;

    uint8 internal immutable _PRIMARY_INDEX;
    uint8 internal immutable SECONDARY_INDEX;
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    uint8 internal immutable DECIMALS_1;
    uint8 internal immutable DECIMALS_2;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;

    function NUM_TOKENS() internal pure override returns (uint256) { return _NUM_TOKENS; }
    function PRIMARY_INDEX() internal view override returns (uint256) { return _PRIMARY_INDEX; }
    function POOL_TOKEN() internal view override returns (IERC20) { return CURVE_POOL_TOKEN; }
    function POOL_PRECISION() internal pure override returns (uint256) { return CURVE_PRECISION; }
    function TOKENS() public view override returns (IERC20[] memory, uint8[] memory) {
        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        uint8[] memory decimals = new uint8[](_NUM_TOKENS);

        (tokens[0], decimals[0]) = (IERC20(TOKEN_1), DECIMALS_1);
        (tokens[1], decimals[1]) = (IERC20(TOKEN_2), DECIMALS_2);

        return (tokens, decimals);
    }

    constructor(
        NotionalProxy notional_,
        DeploymentParams memory params
    ) SingleSidedLPVaultBase(notional_, params.tradingModule) {
        CURVE_POOL = params.pool;
        CURVE_INTERFACE = params.curveInterface;
        CURVE_POOL_TOKEN = IERC20(params.poolToken);

        address primaryToken = _getNotionalUnderlyingToken(params.primaryBorrowCurrencyId);

        // We interact with curve pools directly so we never pass the token addresses back
        // to the curve pools. The amounts are passed back based on indexes instead. Therefore
        // we can rewrite the token addresses from ALT Eth (0xeeee...) back to (0x0000...) which
        // is used by the vault internally to represent ETH.
        TOKEN_1 = _rewriteAltETH(ICurvePool(CURVE_POOL).coins(0));
        TOKEN_2 = _rewriteAltETH(ICurvePool(CURVE_POOL).coins(1));
        _PRIMARY_INDEX = TOKEN_1 == primaryToken ? 0 : 1;
        SECONDARY_INDEX = 1 - _PRIMARY_INDEX;
        
        DECIMALS_1 = TokenUtils.getDecimals(TOKEN_1);
        DECIMALS_2 = TokenUtils.getDecimals(TOKEN_2);
        PRIMARY_DECIMALS = _PRIMARY_INDEX == 0 ? DECIMALS_1 : DECIMALS_2;
        SECONDARY_DECIMALS = _PRIMARY_INDEX == 0 ? DECIMALS_2 : DECIMALS_1;
    }

    function _rewriteAltETH(address token) private pure returns (address) {
        return token == address(Deployments.ALT_ETH_ADDRESS) ? Deployments.ETH_ADDRESS : address(token);
    }

    function _checkReentrancyContext() internal override {
        uint256[2] memory minAmounts;
        if (CURVE_INTERFACE == CurveInterface.V1) {
            ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(0, minAmounts);
        } else if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
            // Total supply on stable swap has a non-reentrant lock
            ICurveStableSwapNG(CURVE_POOL).totalSupply();
        } else if (CURVE_INTERFACE == CurveInterface.V2) {
            // Curve V2 does a `-1` on the liquidity amount so set the amount removed to 1 to
            // avoid an underflow.
            ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(1, minAmounts, true, address(this));
        } else {
            revert();
        }
    }
}