import json
import re
from brownie import network, Contract

def getDependencies(bytecode):
    deps = set()
    for marker in re.findall("_{1,}[^_]*_{1,}", bytecode):
        deps.add(marker)
    result = list(deps)
    return result

def deployArtifact(path, constructorArgs, deployer, name, libs):
    with open(path, "r") as a:
        artifact = json.load(a)

    code = artifact["bytecode"]

    # Resolve dependencies
    deps = getDependencies(code)
    for dep in deps:
        library = dep.strip("_")
        code = code.replace(dep, libs[library][-40:])

    createdContract = network.web3.eth.contract(abi=artifact["abi"], bytecode=code)
    txn = createdContract.constructor(*constructorArgs).buildTransaction(
        {"from": deployer.address, "nonce": deployer.nonce}
    )
    # This does a manual deployment of a contract
    tx_receipt = deployer.transfer(data=txn["data"])

    return Contract.from_abi(name, tx_receipt.contract_address, abi=artifact["abi"], owner=deployer)
