// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {
    ConvexVaultDeploymentParams, 
    Curve2TokenConvexStrategyContext, 
    Curve2TokenPoolContext
} from "../vaults/curve/CurveVaultTypes.sol";
import {TwoTokenPoolUtils} from "../vaults/common/internal/pool/TwoTokenPoolUtils.sol";
import {TwoTokenPoolContext} from "../vaults/common/VaultTypes.sol";
import {Curve2TokenVaultMixin} from "../vaults/curve/mixins/Curve2TokenVaultMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {Curve2TokenPoolUtils} from "../vaults/curve/internal/pool/Curve2TokenPoolUtils.sol";
import {BalancerConstants} from "../vaults/balancer/internal/BalancerConstants.sol";

contract MockCurve2TokenConvexVault is Curve2TokenVaultMixin {
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    mapping(address => uint256) public valuationFactors;

    constructor(
        NotionalProxy notional_, 
        ConvexVaultDeploymentParams memory params
    ) Curve2TokenVaultMixin(notional_, params) { }

    function setValuationFactor(address account, uint256 valuationFactor_) external {
        valuationFactors[account] = valuationFactor_;
    }

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Curve2TokenConvexVault"));
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
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        (uint256 spotPrice, uint256 oraclePrice) = context.poolContext._getSpotPriceAndOraclePrice(context.baseStrategy);
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            strategyTokenAmount: strategyTokenAmount,
            oraclePrice: oraclePrice,
            spotPrice: spotPrice
        });
        if (valuationFactor > 0) {
            underlyingValue = underlyingValue * int256(valuationFactor) / 1e8;            
        }
    }

    function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 minPoolClaim) 
        external returns (uint256) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        return Curve2TokenPoolUtils._joinPoolAndStake(
            context.poolContext, context.baseStrategy, context.stakingContext, primaryAmount, secondaryAmount, minPoolClaim
        );
    }

    function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        (uint256 spotPrice, uint256 oraclePrice) = context.poolContext._getSpotPriceAndOraclePrice(context.baseStrategy);
        return context.poolContext.basePool._getTimeWeightedPrimaryBalance({
            strategyContext: context.baseStrategy,
            poolClaim: bptAmount,
            oraclePrice: oraclePrice,
            spotPrice: spotPrice
        });
    }
}
