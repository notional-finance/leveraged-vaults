import json
from brownie import network, Contract

def deployArtifact(path, constructorArgs, deployer, name):
    with open(path, "r") as a:
        artifact = json.load(a)

    createdContract = network.web3.eth.contract(abi=artifact["abi"], bytecode=artifact["bytecode"])
    txn = createdContract.constructor(*constructorArgs).buildTransaction(
        {"from": deployer.address, "nonce": deployer.nonce}
    )
    # This does a manual deployment of a contract
    tx_receipt = deployer.transfer(data=txn["data"])

    return Contract.from_abi(name, tx_receipt.contract_address, abi=artifact["abi"], owner=deployer)