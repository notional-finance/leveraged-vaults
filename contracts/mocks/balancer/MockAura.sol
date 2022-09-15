// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../../../interfaces/IERC20.sol";
import {IAuraBooster} from "../../../interfaces/aura/IAuraBooster.sol";
import {IAuraRewardPool} from "../../../interfaces/aura/IAuraRewardPool.sol";
import {IAuraStakingProxy} from "../../../interfaces/aura/IAuraStakingProxy.sol";

contract MockAura is IAuraBooster, IAuraRewardPool, IAuraStakingProxy {
    address public balancerPoolToken;
    address public crv;
    address public cvx;
    mapping(address => uint256) public deposits;
    uint256 public pid;

    constructor(uint256 _pid, address _balancerPoolToken, address _crv, address _cvx) {
        pid = _pid;
        balancerPoolToken = _balancerPoolToken;
        crv = _crv;
        cvx = _cvx;
    }

    function deposit(uint256 pid, uint256 amount, bool stake) external returns(bool) {
        deposits[msg.sender] += amount;
        IERC20(balancerPoolToken).transferFrom(msg.sender, address(this), amount);
        return true;
    }

    function stakerRewards() external view returns(address) {
        return address(this);
    }

    function withdrawAndUnwrap(uint256 amount, bool claim) external returns(bool) {
        deposits[msg.sender] -= amount;
        IERC20(balancerPoolToken).transfer(msg.sender, amount);
        return true;
    }

    function getReward(address _account, bool _claimExtras) external returns(bool) {
        return true;
    }

    function balanceOf(address _account) external view returns(uint256) {
        return deposits[_account];
    }

    function operator() external view returns(address) {
        return address(this);
    }
}
