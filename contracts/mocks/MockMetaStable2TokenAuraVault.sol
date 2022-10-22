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

    function testFunc(uint256 bptAmount) public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        uint256 oraclePairPrice = TwoTokenPoolUtils._getOraclePairPrice(
            context.poolContext, context.baseStrategy.tradingModule
        );
        uint256 spotPrice = Stable2TokenOracleMath._getSpotPrice(
            context.oracleContext, context.poolContext, context.poolContext.primaryIndex
        );

        Stable2TokenOracleMath._checkPriceLimit(context.baseStrategy, oraclePairPrice, spotPrice);

        uint256 totalBPTSupply = context.poolContext.basePool.pool.totalSupply();
        uint256 primaryBalance = context.poolContext.primaryBalance * bptAmount / totalBPTSupply;
        uint256 secondaryBalance = context.poolContext.secondaryBalance * bptAmount / totalBPTSupply;

        // Value the secondary balance in terms of the primary token using the oraclePairPrice
        uint256 secondaryAmountInPrimary = secondaryBalance * BalancerConstants.BALANCER_PRECISION / spotPrice;

        uint256 primaryPrecision = 10 ** context.poolContext.primaryDecimals;
        uint256 primaryAmount = (primaryBalance + secondaryAmountInPrimary) * primaryPrecision / BalancerConstants.BALANCER_PRECISION;

        return (oraclePairPrice, spotPrice, totalBPTSupply, primaryBalance, secondaryBalance, secondaryAmountInPrimary, primaryAmount);

        // Make sure spot price is within oracleDeviationLimit of pairPrice
        /*
        
        // Get shares of primary and secondary balances with the provided bptAmount


        // Make sure primaryAmount is reported in primaryPrecision */
    }
}
