import json
import os
from brownie import interface
from brownie.network.contract import Contract


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

pools = {
    "42161": {
        "Curve": {
            "FRAX_USDC_e": "0xdb08f663e5D765949054785F2eD1b2aa1e9C22Cf",
        },
        "Balancer": {
            "rETH_ETH": "0x3Df035433cFACE65b6D68b77CC916085d020C8B8",
            "USDC_4POOL": "0x8Ae7A8789A81A43566d0ee70264252c0DB826940",
            "wstETH_ETH": "0x0E8C1A069f40D0E8Fa861239D3e62003cBF3dCB2"
        }
    }
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

