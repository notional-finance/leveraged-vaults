// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {Constants} from "../../../global/Constants.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";
import {TwoTokenPoolContext, StrategyContext} from "../../common/VaultTypes.sol";
import {Curve2TokenPoolContext, ConvexVaultDeploymentParams, Curve2TokenConvexStrategyContext} from "../CurveVaultTypes.sol";
import {CurveConstants} from "../internal/CurveConstants.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {
    ICurvePool,
    ICurvePoolV1,
    ICurvePoolV2,
    ICurve2TokenPool
} from "../../../../interfaces/curve/ICurvePool.sol";
import {SingleSidedLPVaultBase} from "../../common/SingleSidedLPVaultBase.sol";

abstract contract Curve2TokenPoolMixin is SingleSidedLPVaultBase {
    uint256 internal constant _NUM_TOKENS = 2;
    uint256 internal constant CURVE_PRECISION = 1e18;

    address internal immutable CURVE_POOL;
    IERC20 internal immutable CURVE_POOL_TOKEN;
    bool internal immutable IS_CURVE_V2;

    uint256 internal immutable _PRIMARY_INDEX;
    uint256 internal immutable SECONDARY_INDEX;
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    uint8 internal immutable DECIMALS_1;
    uint8 internal immutable DECIMALS_2;

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
        ConvexVaultDeploymentParams memory params
    ) SingleSidedLPVaultBase(notional_, params.baseParams.tradingModule) {
        CURVE_POOL = params.baseParams.pool;

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
        CURVE_POOL_TOKEN = params.baseParams.isSelfLPToken ? IERC20(CURVE_POOL) : (
            IS_CURVE_V2 ? 
                IERC20(ICurvePoolV2(address(CURVE_POOL)).token()) :
                IERC20(ICurvePoolV1(address(CURVE_POOL)).lp_token())
        );

        address primaryToken = _getNotionalUnderlyingToken(params.baseParams.primaryBorrowCurrencyId);
        // Curve uses ALT_ETH_ADDRESS
        if (primaryToken == Deployments.ETH_ADDRESS) {
            primaryToken = Deployments.ALT_ETH_ADDRESS;
        }

        TOKEN_1 = ICurvePool(CURVE_POOL).coins(0);
        TOKEN_2 = ICurvePool(CURVE_POOL).coins(1);
        _PRIMARY_INDEX = TOKEN_1 == primaryToken ? 0 : 1;
        SECONDARY_INDEX = 1 - _PRIMARY_INDEX;
        
        DECIMALS_1 = TokenUtils.getDecimals(TOKEN_1);
        DECIMALS_2 = TokenUtils.getDecimals(TOKEN_2);
    }

    function _validateRewardToken(address token) internal override view {
        // TODO
    }

    function _twoTokenPoolContext() internal view returns (Curve2TokenPoolContext memory) {
        // return Curve2TokenPoolContext({
        //     basePool: TwoTokenPoolContext({
        //         primaryToken: PRIMARY_TOKEN,
        //         secondaryToken: SECONDARY_TOKEN,
        //         primaryIndex: PRIMARY_INDEX,
        //         secondaryIndex: SECONDARY_INDEX,
        //         primaryDecimals: PRIMARY_DECIMALS,
        //         secondaryDecimals: SECONDARY_DECIMALS,
        //         primaryBalance: ICurvePool(CURVE_POOL).balances(PRIMARY_INDEX),
        //         secondaryBalance: ICurvePool(CURVE_POOL).balances(SECONDARY_INDEX),
        //         poolToken: CURVE_POOL_TOKEN
        //     }),
        //     curvePool: CURVE_POOL,
        //     isV2: IS_CURVE_V2
        // });
    }

    function _checkReentrancyContext() internal override {
        // We need to set the LP token amount to 1 for Curve V2 pools to bypass
        // the underflow check
        uint256[2] memory minAmounts;
        ICurve2TokenPool(address(CURVE_POOL)).remove_liquidity(IS_CURVE_V2 ? 1 : 0, minAmounts);
    }


    uint256[40] private __gap; // Storage gap for future potential upgrades
}
