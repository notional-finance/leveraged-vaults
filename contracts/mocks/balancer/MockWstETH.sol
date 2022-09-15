// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWstETH is ERC20 {
    address public stETH;
    uint256 public rate;

    /**
     * @param _stETH address of the StETH token to wrap
     */
    constructor(address _stETH)
        public
        ERC20("Wrapped liquid staked Ether 2.0", "wstETH")
    {
        stETH = _stETH;
        rate = 1e18;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    /**
     * @notice Exchanges stETH to wstETH
     * @param _stETHAmount amount of stETH to wrap in exchange for wstETH
     * @dev Requirements:
     *  - `_stETHAmount` must be non-zero
     *  - msg.sender must approve at least `_stETHAmount` stETH to this
     *    contract.
     *  - msg.sender must have at least `_stETHAmount` of stETH.
     * User should first approve _stETHAmount to the WstETH contract
     * @return Amount of wstETH user receives after wrap
     */
    function wrap(uint256 _stETHAmount) external returns (uint256) {
        require(_stETHAmount > 0, "wstETH: can't wrap zero stETH");
        uint256 invRate = 1e36 / rate;
        uint256 wstETHAmount = invRate * _stETHAmount;
        _mint(msg.sender, wstETHAmount);
        IERC20(stETH).transferFrom(msg.sender, address(this), _stETHAmount);
        return wstETHAmount;
    }

    /**
     * @notice Exchanges wstETH to stETH
     * @param _wstETHAmount amount of wstETH to uwrap in exchange for stETH
     * @dev Requirements:
     *  - `_wstETHAmount` must be non-zero
     *  - msg.sender must have at least `_wstETHAmount` wstETH.
     * @return Amount of stETH user receives after unwrap
     */
    function unwrap(uint256 _wstETHAmount) external returns (uint256) {
        require(_wstETHAmount > 0, "wstETH: zero amount unwrap not allowed");
        uint256 stETHAmount = rate * _wstETHAmount;
        _burn(msg.sender, _wstETHAmount);
        IERC20(stETH).transfer(msg.sender, stETHAmount);
        return stETHAmount;
    }

    /**
     * @notice Get amount of stETH for a given amount of wstETH
     * @param _wstETHAmount amount of wstETH
     * @return Amount of stETH for a given wstETH amount
     */
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return rate * _wstETHAmount / 1e18;
    }

    /**
     * @notice Get amount of stETH for a one wstETH
     * @return Amount of stETH for 1 wstETH
     */
    function stEthPerToken() external view returns (uint256) {
        return rate;
    }
}
