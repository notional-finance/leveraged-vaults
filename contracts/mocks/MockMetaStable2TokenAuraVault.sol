// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    AuraVaultDeploymentParams, 
    MetaStable2TokenAuraStrategyContext, 
    Balancer2TokenPoolContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {MetaStable2TokenVaultMixin} from "../vaults/balancer/mixins/MetaStable2TokenVaultMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {Balancer2TokenPoolUtils} from "../vaults/balancer/internal/pool/Balancer2TokenPoolUtils.sol";
import {Stable2TokenOracleMath} from "../vaults/balancer/internal/math/Stable2TokenOracleMath.sol";
import {BalancerConstants} from "../vaults/balancer/internal/BalancerConstants.sol";

contract MockMetaStable2TokenAuraVault is MetaStable2TokenVaultMixin {
    using Balancer2TokenPoolUtils for Balancer2TokenPoolContext;

    mapping(address => uint256) public valuationFactors;

    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params
    ) MetaStable2TokenVaultMixin(notional_, params) { }

    function setValuationFactor(address account, uint256 valuationFactor_) external {
        valuationFactors[account] = valuationFactor_;
    }

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("MetaStable2TokenAuraVault"));
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
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
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
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        return Balancer2TokenPoolUtils._joinPoolAndStake(
            context.poolContext, context.baseStrategy, context.stakingContext, primaryAmount, secondaryAmount, minBPT
        );
    }

    function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        return Balancer2TokenPoolUtils._getTimeWeightedPrimaryBalance(
            context.poolContext, context.oracleContext, context.baseStrategy, bptAmount
        );
    }
}
