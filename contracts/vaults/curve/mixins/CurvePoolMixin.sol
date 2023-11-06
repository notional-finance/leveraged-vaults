// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyContext} from "../../common/VaultTypes.sol";
import {ConvexVaultDeploymentParams} from "../CurveVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {Constants} from "../../../global/Constants.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {ICurvePool, ICurvePoolV1, ICurvePoolV2} from "../../../../interfaces/curve/ICurvePool.sol";
import {ConvexStakingMixin} from "./ConvexStakingMixin.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {StrategyUtils} from "../../common/internal/strategy/StrategyUtils.sol";
import {CurveConstants} from "../internal/CurveConstants.sol";

abstract contract CurvePoolMixin is ConvexStakingMixin {
    using StrategyUtils for StrategyContext;

    address internal immutable CURVE_POOL;
    IERC20 internal immutable CURVE_POOL_TOKEN;
    bool internal immutable IS_CURVE_V2;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        ConvexStakingMixin(notional_, params) {

        CURVE_POOL = params.baseParams.pool;

        bool isCurveV2 = false;

        if (Deployments.CHAIN_ID == Constants.CHAIN_ID_MAINNET) {
            address[10] memory handlers = 
                Deployments.CURVE_META_REGISTRY.get_registry_handlers_from_pool(address(CURVE_POOL));

            /// @dev unknown Curve version
            require(handlers[0] == Deployments.CURVE_V1_HANDLER || handlers[0] == Deployments.CURVE_V2_HANDLER);
            isCurveV2 = (handlers[0] == Deployments.CURVE_V2_HANDLER);
        }

        IS_CURVE_V2 = isCurveV2;

        CURVE_POOL_TOKEN = params.baseParams.isSelfLPToken ? IERC20(CURVE_POOL) : (
            IS_CURVE_V2 ? 
                IERC20(ICurvePoolV2(address(CURVE_POOL)).token()) :
                IERC20(ICurvePoolV1(address(CURVE_POOL)).lp_token())
        );
    }

    function _baseStrategyContext() internal view override returns(StrategyContext memory) {
        return StrategyContext({
            tradingModule: TRADING_MODULE,
            vaultSettings: VaultStorage.getStrategyVaultSettings(),
            vaultState: VaultStorage.getStrategyVaultState(),
            poolClaimPrecision: CurveConstants.CURVE_PRECISION,
            canUseStaticSlippage: _canUseStaticSlippage()
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
