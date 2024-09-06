// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "@deployments/Deployments.sol";
import "@contracts/vaults/common/VaultRewarderLib.sol";

contract DeployVaultRewarderLib is Script, Test {
    function run() public {
        require(block.chainid == Deployments.CHAIN_ID, "Invalid Chain");

        // In this code, the trading module proxy has already been deployed.
        vm.startBroadcast();
        address impl = address(new VaultRewarderLib());
        vm.stopBroadcast();
        console.log("VaultRewarderLib deployed at", impl);
    }
}