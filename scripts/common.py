import json
import re
from brownie import network, Contract

def getDependencies(bytecode):
    deps = set()
    for marker in re.findall("_{1,}[^_]*_{1,}", bytecode):
        deps.add(marker)
    result = list(deps)
    return result

def deployArtifact(path, constructorArgs, deployer, name, libs=None):
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

def get_vault_config(**kwargs):
    return [
        kwargs.get("flags", 0),  # 0: flags
        kwargs.get("currencyId", 1),  # 1: currency id
        kwargs.get("minAccountBorrowSize", 100_000),  # 2: min account borrow size
        kwargs.get("minCollateralRatioBPS", 2000),  # 3: 20% collateral ratio
        kwargs.get("feeRate5BPS", 20),  # 4: 1% fee
        kwargs.get("liquidationRate", 104),  # 5: 4% liquidation discount
        kwargs.get("reserveFeeShare", 20),  # 6: 20% reserve fee share
        kwargs.get("maxBorrowMarketIndex", 2),  # 7: 20% reserve fee share
        kwargs.get("maxDeleverageCollateralRatioBPS", 4000),  # 8: 40% max collateral ratio
        kwargs.get("secondaryBorrowCurrencies", [0, 0, 0]),  # 9: none set
    ]

def set_flags(flags, **kwargs):
    binList = list(format(flags, "b").rjust(16, "0"))
    if "ENABLED" in kwargs:
        binList[0] = "1"
    if "ALLOW_ROLL_POSITION" in kwargs:
        binList[1] = "1"
    if "ONLY_VAULT_ENTRY" in kwargs:
        binList[2] = "1"
    if "ONLY_VAULT_EXIT" in kwargs:
        binList[3] = "1"
    if "ONLY_VAULT_ROLL" in kwargs:
        binList[4] = "1"
    if "ONLY_VAULT_DELEVERAGE" in kwargs:
        binList[5] = "1"
    if "ONLY_VAULT_SETTLE" in kwargs:
        binList[6] = "1"
    if "TRANSFER_SHARES_ON_DELEVERAGE" in kwargs:
        binList[7] = "1"
    if "ALLOW_REENTRNACY" in kwargs:
        binList[8] = "1"
    return int("".join(reversed(binList)), 2)
