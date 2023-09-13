// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IAuraBoosterBase {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
}

interface IAuraBooster is IAuraBoosterBase {
    function stakerRewards() external view returns(address);
}

interface IAuraBoosterLite is IAuraBoosterBase {
    function crv() external view returns(address);
    function rewards() external view returns(address);
}
