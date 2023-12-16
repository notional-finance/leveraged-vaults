// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IERC20} from "../IERC20.sol";

interface IBalancerPool is IERC20 {
    function getScalingFactors() external view returns (uint256[] memory);
    function getPoolId() external view returns (bytes32); 
    function getSwapFeePercentage() external view returns (uint256);
}

interface IWeightedPool is IBalancerPool {
    function getNormalizedWeights() external view returns (uint256[] memory);
    function getActualSupply() external view returns (uint256);
}

interface IComposablePool is IBalancerPool {
    function getAmplificationParameter() external view returns (
        uint256 value,
        bool isUpdating,
        uint256 precision
    );
    function getActualSupply() external view returns (uint256);
}