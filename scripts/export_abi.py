import json

from brownie.project import LeveragedVaultsProject

def write_abi(name):
    abi = LeveragedVaultsProject._build.get(name)["abi"]
    with open("abi/{}.json".format(name), "w") as f:
        json.dump(abi, f, sort_keys=True, indent=4)


def main():
    abis = ["TradingModule", "MetaStable2TokenAuraVault", "Boosted3TokenAuraVault"]
    for abi in abis:
        write_abi(abi)
