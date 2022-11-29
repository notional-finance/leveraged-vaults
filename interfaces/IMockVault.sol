// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IMockVault {
    function valuationFactors(address account) external view returns (uint256);
    function setValuationFactor(address account, uint256 valuationFactor_) external;
    function joinPoolAndStake(uint256 primaryAmount, uint256 secondaryAmount, uint256 minBPT) external returns (uint256);
    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) external view returns (int256 underlyingValue);
    function getTimeWeightedPrimaryBalance(uint256 bptAmount) external view returns (uint256);
}