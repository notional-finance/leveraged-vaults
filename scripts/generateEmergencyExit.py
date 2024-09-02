import json
import os
from brownie import interface, network
from brownie.network.contract import Contract

pools = json.load(open("vaults.json", "r"))

def gnosisBatch(network, txns):
    if network == "mainnet":
        chainId = 1
    elif network == "arbitrum":
        chainId = 42161

    return {
        "chainId": str(chainId),
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
    # Can only generate exits for one network at a time
    networkName = network.show_active()
    if networkName == "arbitrum-one":
        networkName = "arbitrum"

    for (n, protocol) in pools.items():
        if n != networkName:
            continue
        for (protocol, vaults) in protocol.items():
            allVaultTxns = []
            for (vaultName, vaultAddress) in vaults.items():
                txn = transactionTemplate(vaultAddress)
                allVaultTxns.append(txn)

                os.makedirs('./emergency/%s/%s' % (n, protocol), exist_ok=True)

                # Individual txn
                with open('./emergency/%s/%s/%s.json' % (n, protocol, vaultName), 'w') as f:
                    json.dump(gnosisBatch(n, [txn]), f, indent=2)

            # All for a protocol
            with open('./emergency/%s/%s.json' % (n, protocol), 'w') as f:
                json.dump(gnosisBatch(n, allVaultTxns), f, indent=2)

