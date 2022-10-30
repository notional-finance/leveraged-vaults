// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AuraVaultDeploymentParams, MetaStable2TokenAuraStrategyContext} from "../vaults/balancer/BalancerVaultTypes.sol";
import {MetaStable2TokenAuraVault} from "../vaults/MetaStable2TokenAuraVault.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/pool/TwoTokenPoolUtils.sol";
import {Stable2TokenOracleMath} from "../vaults/balancer/internal/math/Stable2TokenOracleMath.sol";
import {BalancerConstants} from "../vaults/balancer/internal/BalancerConstants.sol";

contract MockMetaStable2TokenAuraVault is MetaStable2TokenAuraVault {
    mapping(address => uint256) public valuationFactors;

    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params
    ) MetaStable2TokenAuraVault(notional_, params) {
    }

    function setValuationFactor(address account, uint256 valuationFactor_) external {
        valuationFactors[account] = valuationFactor_;
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        uint256 valuationFactor = valuationFactors[account];
        underlyingValue = super.convertStrategyToUnderlying(account, strategyTokenAmount, maturity);
        if (valuationFactor > 0) {
            underlyingValue = underlyingValue * int256(valuationFactor) / 1e8;            
        }
    }

    function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 minBPT) 
        external returns (uint256) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        return TwoTokenPoolUtils._joinPoolAndStake(
            context.poolContext, context.baseStrategy, context.stakingContext, primaryAmount, secondaryAmount, minBPT
        );
    }
}
