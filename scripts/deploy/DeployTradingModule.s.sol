// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "./GnosisHelper.s.sol";
import "@deployments/Deployments.sol";
import "../../contracts/trading/TradingModule.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract DeployTradingModule is Script, Test, GnosisHelper {
    function run() public {
        require(block.chainid == Deployments.CHAIN_ID, "Invalid Chain");

        // In this code, the trading module proxy has already been deployed.
        vm.startBroadcast();
        address impl = address(new TradingModule(Deployments.NOTIONAL, Deployments.TRADING_MODULE));
        vm.stopBroadcast();

        MethodCall[] memory upgrade = new MethodCall[](1);
        upgrade[0].to = address(Deployments.TRADING_MODULE);
        upgrade[0].callData = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, impl);

        generateBatch("./scripts/deploy/upgradeTradingModule.json", upgrade);
    }
}