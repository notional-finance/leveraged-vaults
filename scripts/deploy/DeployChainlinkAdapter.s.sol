// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "@deployments/Deployments.sol";
import "@contracts/trading/oracles/ChainlinkAdapter.sol";

contract DeployChainlinkAdapater is Script, Test {
    function run() public {
        require(block.chainid == Deployments.CHAIN_ID, "Invalid Chain");
        console.log(msg.sender);

        vm.startBroadcast();
        ChainlinkAdapter adapter = new ChainlinkAdapter({
            // rETH/ETH
            baseToUSDOracle_: AggregatorV2V3Interface(0xF3272CAfe65b190e76caAF483db13424a3e23dD2),
            invertBase_: false,
            // ETH/USD (inverted => USD/ETH)
            quoteToUSDOracle_: AggregatorV2V3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
            invertQuote_: true,
            description_: "Notional rETH/USD Chainlink Adapter",
            sequencerUptimeOracle_: Deployments.SEQUENCER_UPTIME_ORACLE
        });
        vm.stopBroadcast();

        console.log("Latest Answer: ", uint256(adapter.latestAnswer()));
        assertApproxEqRel(adapter.latestAnswer(), 2443.36e18, 0.001e18);
    }
}