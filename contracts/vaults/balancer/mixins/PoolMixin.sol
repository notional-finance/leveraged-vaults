// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {PoolContext, AuraVaultDeploymentParams, StrategyContext} from "../BalancerVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {BalancerStrategyBase} from "../BalancerStrategyBase.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {AuraStakingMixin} from "./AuraStakingMixin.sol";
import {BalancerVaultStorage} from "../internal/BalancerVaultStorage.sol";
import {StrategyUtils} from "../internal/strategy/StrategyUtils.sol";

abstract contract PoolMixin is AuraStakingMixin, BalancerStrategyBase {
    using StrategyUtils for StrategyContext;

    bytes32 internal immutable BALANCER_POOL_ID;
    IERC20 internal immutable BALANCER_POOL_TOKEN;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        AuraStakingMixin(
            params.baseParams.liquidityGauge, params.auraRewardPool, params.baseParams.feeReceiver
        )
        BalancerStrategyBase(notional_, params.baseParams) {
        BALANCER_POOL_ID = params.baseParams.balancerPoolId;
        (address pool, /* */) = Deployments.BALANCER_VAULT.getPool(params.baseParams.balancerPoolId);
        BALANCER_POOL_TOKEN = IERC20(pool);
    }

    function _poolContext() internal view returns (PoolContext memory) {
        return PoolContext({
            pool: BALANCER_POOL_TOKEN,
            poolId: BALANCER_POOL_ID
        });
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return AURA_REWARD_POOL.balanceOf(address(this));
    }

    function _baseStrategyContext() internal view returns(StrategyContext memory) {
        return StrategyContext({
            totalBPTHeld: _bptHeld(),
            settlementPeriodInSeconds: SETTLEMENT_PERIOD_IN_SECONDS,
            tradingModule: TRADING_MODULE,
            vaultSettings: BalancerVaultStorage.getStrategyVaultSettings(),
            vaultState: BalancerVaultStorage.getStrategyVaultState(),
            feeReceiver: FEE_RECEIVER
        });
    }

    /// @notice Converts BPT to strategy tokens
    function convertBPTClaimToStrategyTokens(uint256 bptClaim)
        external view returns (uint256 strategyTokenAmount) {
        return _baseStrategyContext()._convertBPTClaimToStrategyTokens(bptClaim);
    }

    /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount) 
        external view returns (uint256 bptClaim) {
        return _baseStrategyContext()._convertStrategyTokensToBPTClaim(strategyTokenAmount);
    }
}
