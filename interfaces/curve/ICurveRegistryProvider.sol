// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.11;

interface ICurveRegistryProvider {
    function get_registry() external view returns (address);
}
