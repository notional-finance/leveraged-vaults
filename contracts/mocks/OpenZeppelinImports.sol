// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

// Bring these open zeppelin contracts into the build for brownie
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract nUpgradeableBeacon is UpgradeableBeacon {
    constructor(address implementation_) UpgradeableBeacon(implementation_) {}
}
