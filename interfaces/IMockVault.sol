// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {MetaStable2TokenAuraStrategyContext} from "../contracts/vaults/balancer/BalancerVaultTypes.sol";
import {Boosted3TokenAuraStrategyContext} from "../contracts/vaults/balancer/BalancerVaultTypes.sol";
import {Curve2TokenConvexStrategyContext} from "../contracts/vaults/curve/CurveVaultTypes.sol";

interface IMockVault {
    function valuationFactors(address account) external view returns (uint256);
    function setValuationFactor(address account, uint256 valuationFactor_) external;
    function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 poolClaim) external returns (uint256);
    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) external view returns (int256 underlyingValue);
    function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256);
}

interface IBalancer2TokenMetaStableMockVault is IMockVault {
    function getStrategyContext() external view returns (MetaStable2TokenAuraStrategyContext memory);
}

interface IBalancer3TokenBoostedMockVault is IMockVault  {
    function getStrategyContext() external view returns (Boosted3TokenAuraStrategyContext memory);
}

interface ICurve2TokenConvexMockVault is IMockVault  {
    function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory);
}
