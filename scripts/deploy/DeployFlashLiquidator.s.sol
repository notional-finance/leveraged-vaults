
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "@contracts/liquidator/AaveFlashLiquidator.sol";

contract DeployFlashLiquidator is Script {
    function run() public {
        require(block.chainid == Deployments.CHAIN_ID, "Invalid Chain");

        vm.startBroadcast();
        address impl = address(new AaveFlashLiquidator());
        vm.stopBroadcast();
    }
}