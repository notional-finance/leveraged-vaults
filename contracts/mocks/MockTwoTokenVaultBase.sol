// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    OracleContext, 
    TwoTokenPoolContext
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {TwoTokenPoolUtils} from "../vaults/balancer/internal/pool/TwoTokenPoolUtils.sol";

contract MockTwoTokenVaultBase {
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    TwoTokenPoolContext internal poolContext;
    OracleContext private oracleContext;

    constructor(TwoTokenPoolContext memory poolContext_, OracleContext memory oracleContext_) {
        poolContext = poolContext_;
        oracleContext = oracleContext_;
    }

    function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256) {
        return poolContext._getTimeWeightedPrimaryBalance(oracleContext, bptAmount);
    } 

    function getSpotBalances(uint256 bptAmount) 
        external view returns (uint256 primaryBalance, uint256 secondaryBalance) {
        uint256 totalBPTSupply = poolContext.basePool.pool.totalSupply();
        primaryBalance = poolContext.primaryBalance * bptAmount / totalBPTSupply;
        secondaryBalance = poolContext.secondaryBalance * bptAmount / totalBPTSupply;
    }
}
