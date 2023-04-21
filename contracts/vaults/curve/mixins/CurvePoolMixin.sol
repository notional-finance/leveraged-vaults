// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyContext} from "../../common/VaultTypes.sol";
import {ConvexVaultDeploymentParams} from "../CurveVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
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

        address[10] memory handlers = 
            Deployments.CURVE_META_REGISTRY.get_registry_handlers_from_pool(address(CURVE_POOL));

        /// @dev unknown Curve version
        require(handlers[0] == CurveConstants.CURVE_V1_HANDLER || handlers[0] == CurveConstants.CURVE_V2_HANDLER);

        IS_CURVE_V2 = (handlers[0] == CurveConstants.CURVE_V2_HANDLER);

        CURVE_POOL_TOKEN = IS_CURVE_V2 ? 
            IERC20(ICurvePoolV2(address(CURVE_POOL)).token()) :
            IERC20(ICurvePoolV1(address(CURVE_POOL)).lp_token());
    }

    function _baseStrategyContext() internal view returns(StrategyContext memory) {
        return StrategyContext({
            settlementPeriodInSeconds: SETTLEMENT_PERIOD_IN_SECONDS,
            tradingModule: TRADING_MODULE,
            vaultSettings: VaultStorage.getStrategyVaultSettings(),
            vaultState: VaultStorage.getStrategyVaultState(),
            poolClaimPrecision: CurveConstants.CURVE_PRECISION,
            canUseStaticSlippage: _canUseStaticSlippage()
        });
    }

    /// @notice Converts LP tokens to strategy tokens
    function convertPoolClaimToStrategyTokens(uint256 poolClaim)
        external view returns (uint256 strategyTokenAmount) {
        return _baseStrategyContext()._convertPoolClaimToStrategyTokens(poolClaim);
    }

    /// @notice Converts strategy tokens to LP tokens
    function convertStrategyTokensToPoolClaim(uint256 strategyTokenAmount) 
        external view returns (uint256 poolClaim) {
        return _baseStrategyContext()._convertStrategyTokensToPoolClaim(strategyTokenAmount);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
