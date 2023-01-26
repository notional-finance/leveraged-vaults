// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyContext} from "../../common/VaultTypes.sol";
import {ConvexVaultDeploymentParams} from "../CurveVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {ICurvePool} from "../../../../interfaces/curve/ICurvePool.sol";
import {ConvexStakingMixin} from "./ConvexStakingMixin.sol";
import {CurveVaultStorage} from "../internal/CurveVaultStorage.sol";
import {StrategyUtils} from "../../common/internal/strategy/StrategyUtils.sol";
import {CurveConstants} from "../internal/CurveConstants.sol";

abstract contract CurvePoolMixin is ConvexStakingMixin {
    using StrategyUtils for StrategyContext;

    ICurvePool internal immutable CURVE_POOL;
    IERC20 internal immutable CURVE_POOL_TOKEN;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        ConvexStakingMixin(notional_, params) {

        CURVE_POOL = ICurvePool(params.baseParams.pool);
        CURVE_POOL_TOKEN = IERC20(CURVE_POOL.lp_token());
    }

    function _baseStrategyContext() internal view returns(StrategyContext memory) {
        return StrategyContext({
            settlementPeriodInSeconds: SETTLEMENT_PERIOD_IN_SECONDS,
            tradingModule: TRADING_MODULE,
            vaultSettings: CurveVaultStorage.getStrategyVaultSettings(),
            vaultState: CurveVaultStorage.getStrategyVaultState(),
            poolClaimPrecision: CurveConstants.CURVE_PRECISION
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
