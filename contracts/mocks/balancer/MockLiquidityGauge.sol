// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";

contract MockLiquidityGauge is ERC20, ILiquidityGauge {
    address public balancerPoolToken;

    constructor(address _balancerPoolToken) ERC20("Mock Balancer Liquidity Gauge", "BPT-GAUGE") {
        balancerPoolToken = _balancerPoolToken;
    }

    function deposit(uint256 _value) external {
        _mint(msg.sender, _value);
        IERC20(balancerPoolToken).transferFrom(msg.sender, address(this), _value);
    }

    function deposit(uint256 _value, address _addr, bool _claim_rewards) external {
        _mint(_addr, _value);
        IERC20(balancerPoolToken).transferFrom(_addr, address(this), _value);
    }

    function withdraw(uint256 _value, bool claim_rewards) external {
        _burn(msg.sender, _value);
        IERC20(balancerPoolToken).transfer(msg.sender, _value);
    }

    function claim_rewards() external {

    }

    // curve & balancer use lp_token()
    function lp_token() external view returns (address) {
        return balancerPoolToken;
    }

    // angle use staking_token()
    function staking_token() external view returns (address) {
        return balancerPoolToken;
    }

    function reward_tokens(uint256 i) external view returns (address token) {
        return address(0);
    }

    function reward_count() external view returns (uint256 nTokens) {
        return 0;
    }

    function user_checkpoint(address addr) external returns (bool) {
        return true;
    }
}
