pragma solidity 0.8.15;

import {IERC20} from "../IERC20.sol";

interface IMetaStablePool is IERC20 {
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

interface IWeightedPool is IERC20 {
    function getNormalizedWeights() external view returns (uint256[] memory);

    function getMiscData() external view returns (
        int256 logInvariant,
        int256 logTotalSupply,
        uint256 oracleSampleCreationTimestamp,
        uint256 oracleIndex,
        bool oracleEnabled,
        uint256 swapFeePercentage
    );
}
