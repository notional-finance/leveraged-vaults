// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IMockVault} from "../../interfaces/IMockVault.sol";

contract nMockProxy is ERC1967Proxy {
    address public immutable MOCK_IMPL;

    constructor(
        address _logic,
        bytes memory _data,
        address _mockImpl
    ) ERC1967Proxy(_logic, _data) {
        MOCK_IMPL = _mockImpl;
    }

    receive() external payable override {
        // Allow ETH transfers to succeed
    }

    function _implementation() internal view virtual override returns (address impl) {
        if (msg.sig == IMockVault.joinPoolAndStake.selector ||
            msg.sig == IMockVault.convertStrategyToUnderlying.selector ||
            msg.sig == IMockVault.setValuationFactor.selector ||
            msg.sig == IMockVault.valuationFactors.selector ||
            msg.sig == IMockVault.getTimeWeightedPrimaryBalance.selector) {
            return MOCK_IMPL;
        }
        return super._implementation();
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}
