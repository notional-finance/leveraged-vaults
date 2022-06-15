pragma solidity =0.8.11;

import {IERC20} from "../IERC20.sol";

interface IBalancerPool is IERC20 {
    function getNormalizedWeights() external view returns (uint256, uint256);
}
