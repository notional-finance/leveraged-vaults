import json
import requests
from brownie import network

def load_test_data(testName):
    with open("tests/zeroex/{}.data.json".format(network.show_active()), "r") as f:
        data = json.load(f)
    if testName not in data:
        return {
            "blockNumber": 0,
            "params": []
        }
    return data[testName]

def save_test_data(testName, blockNumber, params):
    with open("tests/zeroex/{}.data.json".format(network.show_active()), "r") as f:
        data = json.load(f)
    if testName not in data:
        data[testName] = {}
    data[testName]["blockNumber"] = blockNumber
    data[testName]["params"] = params
    with open("tests/zeroex/{}.data.json".format(network.show_active()), "w") as f:
        json.dump(data, f, indent=4)    

# https://api.0x.org/swap/v1/quote?sellToken=0xba100000625a3754423978a60c9317c58a424e3D&buyToken=ETH&sellAmount=24409825087058625000&slippagePercentage=0.3

def fetch_0x_data(sellToken, buyToken, sellAmount, slippagePercentage):
    active = network.show_active()
    url = ""
    if active == "arbitrum-one" or active == "arbitrum-fork":
        url = "https://arbitrum.api.0x.org/swap/v1/quote"
    elif active == "mainnet" or active == "mainnet-fork":
        url = "https://api.0x.org/swap/v1/quote"
    else:
        raise "Invalid network"
    resp = requests.get(url, {
        "sellToken": sellToken,
        "buyToken": buyToken,
        "sellAmount": sellAmount,
        "slippagePercentage": slippagePercentage
    }, headers={"0x-api-key":"73320f1c-f232-46da-9f6e-a47fc310ea75"})
    return resp.json()["data"]
