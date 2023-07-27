// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    AuraVaultDeploymentParams, 
    MetaStable2TokenAuraStrategyContext, 
    Balancer2TokenPoolContext
} from "../BalancerVaultTypes.sol";
import {StrategyContext} from "../../common/VaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";
import {IMetaStablePool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {StableOracleContext} from "../BalancerVaultTypes.sol";
import {Balancer2TokenPoolMixin} from "./Balancer2TokenPoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {StableMath} from "../internal/math/StableMath.sol";
import {Balancer2TokenPoolUtils} from "../internal/pool/Balancer2TokenPoolUtils.sol";

abstract contract MetaStable2TokenVaultMixin is Balancer2TokenPoolMixin {
    using Balancer2TokenPoolUtils for Balancer2TokenPoolContext;
    using TypeConvert for uint256;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        Balancer2TokenPoolMixin(notional_, params) { }

    function _stableOracleContext() internal view returns (StableOracleContext memory) {
        (
            uint256 value,
            /* bool isUpdating */,
            uint256 precision
        ) = IMetaStablePool(address(BALANCER_POOL_TOKEN)).getAmplificationParameter();
        require(precision == StableMath._AMP_PRECISION);
        
        return StableOracleContext({
            ampParam: value
        });
    }

    function _strategyContext() internal view returns (MetaStable2TokenAuraStrategyContext memory) {
        return MetaStable2TokenAuraStrategyContext({
            poolContext: _twoTokenPoolContext(),
            oracleContext: _stableOracleContext(),
            stakingContext: _auraStakingContext(),
            baseStrategy: _baseStrategyContext()
        });
    }

    function getExchangeRate() public view override returns (int256) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        if (context.baseStrategy.vaultState.totalVaultSharesGlobal == 0) {
            return context.poolContext._getTimeWeightedPrimaryBalance({
                oracleContext: context.oracleContext,
                strategyContext: context.baseStrategy,
                bptAmount: context.baseStrategy.poolClaimPrecision // 1 pool token
            }).toInt();
        } else {
            return context.poolContext._convertStrategyToUnderlying({
                strategyContext: context.baseStrategy,
                oracleContext: context.oracleContext,
                strategyTokenAmount: uint256(Constants.INTERNAL_TOKEN_PRECISION) // 1 vault share
            });
        }
    }

    function getStrategyVaultInfo() public view override returns (StrategyVaultInfo memory) {
        StrategyContext memory context = _baseStrategyContext();
        return StrategyVaultInfo({
            pool: address(BALANCER_POOL_TOKEN),
            singleSidedTokenIndex: PRIMARY_INDEX,
            totalLPTokens: context.vaultState.totalPoolClaim,
            totalVaultShares: context.vaultState.totalVaultSharesGlobal
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
