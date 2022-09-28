pragma solidity 0.8.15;

import {IERC20} from "../IERC20.sol";

interface IBalancerPool {
    function getScalingFactors() external view returns (uint256[] memory);
    function getPoolId() external view returns (bytes32); 
}

interface ILinearPool is IBalancerPool, IERC20 {
    function getMainIndex() external view returns (uint256);
    function getWrappedIndex() external view returns (uint256);
    function getSwapFeePercentage() external view returns (uint256);
    function getVirtualSupply() external view returns (uint256);
    function getTargets() external view returns (uint256 lowerTarget, uint256 upperTarget);
}

interface IBoostedPool is IBalancerPool, IERC20 {
    function getMainToken() external view returns (address);   
    function getWrappedToken() external view returns (address);   
    function getAmplificationParameter() external view returns (
        uint256 value,
        bool isUpdating,
        uint256 precision
    );
    function getDueProtocolFeeBptAmount() external view returns (uint256);
}

interface IMetaStablePool is IBalancerPool, IERC20 {
    function getOracleMiscData() external view returns (
        int256 logInvariant, 
        int256 logTotalSupply, 
        uint256 oracleSampleCreationTimestamp, 
        int256 oracleIndex, 
        bool oracleEnabled
    );

    function getAmplificationParameter() external view returns (
        uint256 value,
        bool isUpdating,
        uint256 precision
    );
}
