// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @dev Re-exporting to make available to brownie
/// UpgradeableBeacon is Ownable, default owner is the deployer
contract nUpgradeableBeacon is UpgradeableBeacon {
    constructor(address implementation_) UpgradeableBeacon(implementation_) {}
}