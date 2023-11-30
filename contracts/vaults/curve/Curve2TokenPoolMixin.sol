// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../interfaces/IERC20.sol";
import {Deployments} from "../../global/Deployments.sol";
import {Constants} from "../../global/Constants.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {
    ICurvePool,
    ICurvePoolV1,
    ICurvePoolV2,
    ICurve2TokenPool
} from "../../../interfaces/curve/ICurvePool.sol";
import {SingleSidedLPVaultBase} from "../common/SingleSidedLPVaultBase.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    address pool;
    ITradingModule tradingModule;
    address poolToken;
}

abstract contract Curve2TokenPoolMixin is SingleSidedLPVaultBase {
    uint256 internal constant _NUM_TOKENS = 2;
    uint256 internal constant CURVE_PRECISION = 1e18;

    address internal immutable CURVE_POOL;
    IERC20 internal immutable CURVE_POOL_TOKEN;
    bool internal immutable IS_CURVE_V2;

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
    function TOKENS() internal view override returns (IERC20[] memory, uint8[] memory) {
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

        bool isCurveV2 = false;
        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            address[10] memory handlers = 
                Deployments.CURVE_META_REGISTRY.get_registry_handlers_from_pool(address(CURVE_POOL));

            require(
                handlers[0] == Deployments.CURVE_V1_HANDLER ||
                handlers[0] == Deployments.CURVE_V2_HANDLER
            ); // @dev unknown Curve version
            isCurveV2 = (handlers[0] == Deployments.CURVE_V2_HANDLER);
        }
        IS_CURVE_V2 = isCurveV2;
        // There are some cases where the pool token address is not directly exposed on the Curve pool
        // itself. In those cases, the pool token address will be manually passed in via the constructor.
        CURVE_POOL_TOKEN = params.poolToken != address(0) ? IERC20(params.poolToken) : (
            IS_CURVE_V2 ? 
                IERC20(ICurvePoolV2(address(CURVE_POOL)).token()) :
                IERC20(ICurvePoolV1(address(CURVE_POOL)).lp_token())
        );

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
        // We need to set the LP token amount to 1 for Curve V2 pools to bypass
        // the underflow check
        uint256[2] memory minAmounts;
        ICurve2TokenPool(address(CURVE_POOL)).remove_liquidity(IS_CURVE_V2 ? 1 : 0, minAmounts);
    }
}
