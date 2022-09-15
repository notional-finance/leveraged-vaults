// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../../../interfaces/balancer/IRateProvider.sol";
import "../../../interfaces/IWstETH.sol";

/**
 * @title Wrapped stETH Rate Provider
 * @notice Returns the value of wstETH in terms of stETH
 */
contract MockWstETHRateProvider is IRateProvider {
    IWstETH public immutable wstETH;

    constructor(IWstETH _wstETH) {
        wstETH = _wstETH;
    }

    /**
     * @return the value of wstETH in terms of stETH
     */
    function getRate() external view override returns (uint256) {
        return wstETH.stEthPerToken();
    }
}
