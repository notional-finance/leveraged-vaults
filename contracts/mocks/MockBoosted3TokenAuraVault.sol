// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    AuraVaultDeploymentParams, 
    Boosted3TokenAuraStrategyContext, 
    Balancer3TokenPoolContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {Boosted3TokenPoolMixin} from "../vaults/balancer/mixins/Boosted3TokenPoolMixin.sol";
import {Balancer3TokenBoostedPoolUtils} from "../vaults/balancer/internal/pool/Balancer3TokenBoostedPoolUtils.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";

contract MockBoosted3TokenAuraVault is Boosted3TokenPoolMixin {
    using Balancer3TokenBoostedPoolUtils for Balancer3TokenPoolContext;

    mapping(address => uint256) public valuationFactors;

    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params
    ) Boosted3TokenPoolMixin(notional_, params) {
    }

    function setValuationFactor(address account, uint256 valuationFactor_) external {
        valuationFactors[account] = valuationFactor_;
    }

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Boosted3TokenAuraVault"));
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {}

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {}

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        uint256 valuationFactor = valuationFactors[account];
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext,
            strategyTokenAmount: strategyTokenAmount
        });
        if (valuationFactor > 0) {
            underlyingValue = underlyingValue * int256(valuationFactor) / 1e8;            
        }
    }

    function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 minBPT) 
        external returns (uint256) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        return Balancer3TokenBoostedPoolUtils._joinPoolAndStake(
            context.poolContext, context.baseStrategy, context.stakingContext, context.oracleContext, primaryAmount, minBPT
        );
    }

    function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        return Balancer3TokenBoostedPoolUtils._getTimeWeightedPrimaryBalance(
            context.poolContext, context.oracleContext, context.baseStrategy, bptAmount
        );
    }
}
