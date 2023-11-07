// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ComposableOracleContext,
    AuraVaultDeploymentParams,
    BalancerComposablePoolContext,
    BalancerComposableAuraStrategyContext,
    AuraStakingContext
} from "../BalancerVaultTypes.sol";
import {StrategyContext, ComposablePoolContext} from "../../common/VaultTypes.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {IBalancerPool, IComposablePool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {AuraStakingMixin} from "./AuraStakingMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {StableMath} from "../internal/math/StableMath.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {ComposableAuraHelper} from "../external/ComposableAuraHelper.sol";
import {BalancerComposablePoolUtils} from "../internal/pool/BalancerComposablePoolUtils.sol";

/**
 * Base class for all Balancer composable pools
 */
abstract contract BalancerComposablePoolMixin is AuraStakingMixin {
    using TypeConvert for uint256;
    using BalancerComposablePoolUtils for ComposablePoolContext;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        AuraStakingMixin(notional_, params) {
        // BPT_INDEX must be defined for a composable pool
        require(BPT_INDEX != NOT_FOUND);
    }

    function _validateRewardToken(address token) internal override view {
        if (
            token == TOKEN_1 ||
            token == TOKEN_2 ||
            token == TOKEN_3 ||
            token == TOKEN_4 ||
            token == TOKEN_5 ||
            token == address(AURA_BOOSTER) ||
            token == address(AURA_REWARD_POOL) ||
            token == address(Deployments.WETH)
        ) { revert(); }
    }

    function _composablePoolContext() internal view returns (BalancerComposablePoolContext memory) {
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        uint256[] memory scalingFactors = IBalancerPool(address(BALANCER_POOL_TOKEN)).getScalingFactors();
        (IERC20[] memory tokens, uint8[] memory decimals) = TOKENS();

        // return BalancerComposablePoolContext({
        //     basePool: ComposablePoolContext({
        //         tokens: tokens,
        //         balances: balances,
        //         decimals: decimals,
        //         poolToken: POOL_TOKEN(),
        //         primaryIndex: PRIMARY_INDEX()
        //     }),
        //     poolId: BALANCER_POOL_ID,
        //     scalingFactors: scalingFactors,
        //     bptIndex: BPT_INDEX
        // });
    }

    /// @notice returns the composable oracle context
    function _composableOracleContext() internal view returns (ComposableOracleContext memory) {
        IComposablePool pool = IComposablePool(address(BALANCER_POOL_TOKEN));

        (
            uint256 value,
            /* bool isUpdating */,
            uint256 precision
        ) = IComposablePool(address(BALANCER_POOL_TOKEN)).getAmplificationParameter();
        require(precision == StableMath._AMP_PRECISION);
        
        return ComposableOracleContext({
            ampParam: value,
            virtualSupply: pool.getActualSupply()
        });
    }

    /// @notice returns the composable pool strategy context
    function _strategyContext() internal view returns (BalancerComposableAuraStrategyContext memory) {
        // return BalancerComposableAuraStrategyContext({
        //     poolContext: _composablePoolContext(),
        //     oracleContext: _composableOracleContext(),
        //     stakingContext: _auraStakingContext(),
        //     baseStrategy: _baseStrategyContext()
        // });
    }

    /// @notice returns the value of 1 vault share
    /// @return exchange rate of 1 vault share
    function getExchangeRate(uint256 /* maturity */) public view override returns (int256) {
        BalancerComposableAuraStrategyContext memory context = _strategyContext();
        return ComposableAuraHelper.getExchangeRate(context);
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
