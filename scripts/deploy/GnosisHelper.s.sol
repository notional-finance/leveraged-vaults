// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Script.sol";

struct MethodCall {
    address to;
    uint256 value;
    bytes callData;
}

contract GnosisHelper is Script {
    function generateBatch(string memory path, MethodCall[] memory calls) internal {
        string memory meta = "meta";
        vm.serializeString(meta, "name", "Transactions Batch");
        meta = vm.serializeString(meta, "txBuilderVersion", "1.16.1");

        string memory id = "base";
        // FIXME: foundry does not properly serialize this to a string
        vm.serializeString(id, "chainId", vm.toString(block.chainid));
        vm.serializeUint(id, "createdAt", block.timestamp * 1000);
        vm.serializeString(id, "version", "1.0");
        // Need to first generate an array of place holder strings to replace later
        vm.serializeString(id, "transactions", new string[](calls.length));
        string memory output = vm.serializeString(id, "meta", meta);
        vm.writeJson(output, path);

        for (uint256 i; i < calls.length; i++) {
            string memory t = "txn";
            vm.serializeAddress(t, "to", calls[i].to);
            // FIXME: foundry does not properly serialize this to a string
            vm.serializeString(t, "value", vm.toString(calls[i].value));
            vm.serializeBytes(t, "data", calls[i].callData);
            string memory txn = _txnTemplate(t);
            // Replaces the transaction at the given offset in the array
            string memory key = string(abi.encodePacked(".transactions[", vm.toString(i), "]"));
            vm.writeJson(txn, path, key);
        }
    }

        
    function _txnTemplate(string memory t) private returns (string memory) {
        string memory method = "contractMethod";
        vm.serializeString(method, "inputs", new string[](0));
        vm.serializeString(method, "name", "fallback");
        method = vm.serializeBool(method, "payable", true);
        return vm.serializeString(t, "contractMethod", method);
    }
}