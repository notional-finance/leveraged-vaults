
pragma solidity 0.8.15;

interface IBalancerMinter {
    function mint(address gauge) external;
    function getBalancerToken() external returns (address);
}
