
pragma solidity 0.8.15;

interface IAuraBooster {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
    function stakerRewards() external view returns(address);
}
