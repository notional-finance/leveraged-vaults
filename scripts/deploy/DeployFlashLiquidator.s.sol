
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "@contracts/liquidator/FlashLiquidator.sol";

contract DeployFlashLiquidator is Script {
    function run() public {
        require(block.chainid == Deployments.CHAIN_ID, "Invalid Chain");

        vm.startBroadcast();
        address impl = address(new FlashLiquidator());
        vm.stopBroadcast();
        console.log("New Liquidator", impl);
    }
}