import json
import os
from brownie import interface
from brownie.network.contract import Contract

pools = json.load(open("vaults.json", "r"))

def gnosisBatch(network, txns):
    return {
        "chainId": network,
        "createdAt": 1701985180000,
        "meta": {
            "name": "Transactions Batch",
            "txBuilderVersion": "1.16.1"
        },
        "transactions": txns,
        "version": 1.0
    }

def transactionTemplate(vault):
    v = Contract.from_abi("", vault, interface.ISingleSidedLPStrategyVault.abi)
    data = v.emergencyExit.encode_input(0, "")

    return {
        "contractMethod": {
            "inputs": [],
            "name": "fallback",
            "payable": True
        },
        "data": data,
        "to": vault,
        "value": "0"
    }


def main():
    for (network, protocol) in pools.items():
        for (protocol, vaults) in protocol.items():
            allVaultTxns = []
            for (vaultName, vaultAddress) in vaults.items():
                txn = transactionTemplate(vaultAddress)
                allVaultTxns.append(txn)

                os.makedirs('./emergency/%s/%s' % (network, protocol), exist_ok=True)

                # Individual txn
                with open('./emergency/%s/%s/%s.json' % (network, protocol, vaultName), 'w') as f:
                    json.dump(gnosisBatch(network, [txn]), f, indent=2)

            # All for a protocol
            with open('./emergency/%s/%s.json' % (network, protocol), 'w') as f:
                json.dump(gnosisBatch(network, allVaultTxns), f, indent=2)

