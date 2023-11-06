// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {StrategyContext} from "../../common/VaultTypes.sol";
import {AuraVaultDeploymentParams} from "../BalancerVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IBalancerVault} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {AuraStakingMixin} from "./AuraStakingMixin.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";

/**
 * Base class for all Balancer LP strategies
 */
abstract contract BalancerPoolMixin is AuraStakingMixin {
    /// @notice Balancer pool ID
    bytes32 internal immutable BALANCER_POOL_ID;
    /// @notice Balancer LP token
    IERC20 internal immutable BALANCER_POOL_TOKEN;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        AuraStakingMixin(notional_, params) {
        BALANCER_POOL_ID = params.baseParams.balancerPoolId;
        (address pool, /* */) = Deployments.BALANCER_VAULT.getPool(params.baseParams.balancerPoolId);
        BALANCER_POOL_TOKEN = IERC20(pool);
    }

    /// @notice the re-entrancy context is checked during liquidation
    function _checkReentrancyContext() internal override {
        IBalancerVault.UserBalanceOp[] memory noop = new IBalancerVault.UserBalanceOp[](0);
        Deployments.BALANCER_VAULT.manageUserBalance(noop);
    }

    /// @notice returns the base strategy context
    function _baseStrategyContext() internal view override returns (StrategyContext memory) {
        return StrategyContext({
            tradingModule: TRADING_MODULE,
            vaultSettings: VaultStorage.getStrategyVaultSettings(),
            vaultState: VaultStorage.getStrategyVaultState(),
            poolClaimPrecision: BalancerConstants.BALANCER_PRECISION,
            canUseStaticSlippage: _canUseStaticSlippage()
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
