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
import {MetaStable2TokenAuraHelper} from "../external/MetaStable2TokenAuraHelper.sol";

abstract contract MetaStable2TokenVaultMixin is Balancer2TokenPoolMixin {
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

    function getExchangeRate(uint256 /* maturity */) public view override returns (int256) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        return MetaStable2TokenAuraHelper.getExchangeRate(context);
    }

    function getStrategyVaultInfo() public view override returns (SingleSidedLPStrategyVaultInfo memory) {
        StrategyContext memory context = _baseStrategyContext();
        return SingleSidedLPStrategyVaultInfo({
            pool: address(BALANCER_POOL_TOKEN),
            singleSidedTokenIndex: PRIMARY_INDEX,
            totalLPTokens: context.vaultState.totalPoolClaim,
            totalVaultShares: context.vaultState.totalVaultSharesGlobal
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
