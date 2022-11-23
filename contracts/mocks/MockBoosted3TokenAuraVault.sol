// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AuraVaultDeploymentParams, Boosted3TokenAuraStrategyContext} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Boosted3TokenAuraVault} from "../vaults/Boosted3TokenAuraVault.sol";
import {Boosted3TokenPoolUtils} from "../vaults/balancer/internal/pool/Boosted3TokenPoolUtils.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";

contract MockBoosted3TokenAuraVault is Boosted3TokenAuraVault {
    mapping(address => uint256) public valuationFactors;

    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params
    ) Boosted3TokenAuraVault(notional_, params) {
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
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        return Boosted3TokenPoolUtils._joinPoolAndStake(
            context.poolContext, context.baseStrategy, context.stakingContext, context.oracleContext, primaryAmount, minBPT
        );
    }
}
