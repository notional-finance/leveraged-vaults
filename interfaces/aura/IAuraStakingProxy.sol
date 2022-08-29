
pragma solidity 0.8.15;

interface IAuraStakingProxy {
    function crv() external view returns(address);
    function cvx() external view returns(address);
}
