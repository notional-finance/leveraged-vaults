// // SPDX-License-Identifier: MIT
// pragma solidity >=0.7.6;

// import {BalancerComposableAuraStrategyContext} from "../contracts/vaults/balancer/BalancerVaultTypes.sol";
// import {Curve2TokenConvexStrategyContext} from "../contracts/vaults/curve/CurveVaultTypes.sol";

// interface IMockVault {
//     function valuationFactors(address account) external view returns (uint256);
//     function setValuationFactor(address account, uint256 valuationFactor_) external;
//     function convertStrategyToUnderlying(
//         address account,
//         uint256 strategyTokenAmount,
//         uint256 maturity
//     ) external view returns (int256 underlyingValue);
//     function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256);
// }


// interface IBalancerComposableMockVault is IMockVault {
//     function getStrategyContext() external view returns (BalancerComposableAuraStrategyContext memory);
//     function joinPoolAndStake(uint256[] calldata amounts, uint256 poolClaim) external returns (uint256);
// }

// interface ICurve2TokenConvexMockVault is IMockVault  {
//     function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory);
//     function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 poolClaim) external returns (uint256);
// }
