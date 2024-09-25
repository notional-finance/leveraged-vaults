import json

from brownie.project import LeveragedVaultsProject

def write_abi(name):
    abi = LeveragedVaultsProject._build.get(name)["abi"]
    with open("abi/{}.json".format(name), "w") as f:
        json.dump(abi, f, sort_keys=True, indent=4)

def merge_abis(abi1, abi2):
    """
    Merge two JSON objects into a single object.
    If there are duplicate keys, the value from obj2 will overwrite obj1.
    """
    a1 = LeveragedVaultsProject._build.get(abi1)["abi"]
    a2 = LeveragedVaultsProject._build.get(abi2)["abi"]
    a1.extend(a2)

    with open("abi/{}.json".format(abi1), "w") as f:
        json.dump(a1, f, sort_keys=True, indent=4)

def main():
    abis = [
        "TradingModule",
        "FlashLiquidator",
        "PendlePTGeneric"
    ]
    for abi in abis:
        write_abi(abi)

    # Merge single sided lp with vault rewarder lib
    merge_abis("ISingleSidedLPStrategyVault", "VaultRewarderLib")
    
