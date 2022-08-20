import json
from brownie import network

addresses = {}
with open("v2.mainnet.json", "r") as f:
    addresses["mainnet"] = json.load(f)

with open("v2.goerli.json", "r") as f:
    addresses["goerli"] = json.load(f)

def get_addresses():
    networkName = network.show_active()
    if networkName == "mainnet-fork":
        networkName = "mainnet"
    if networkName == "goerli-fork":
        networkName = "goerli"
    return (networkName, addresses[networkName])

