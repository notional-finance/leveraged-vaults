import json
import requests

def load_test_data(testName):
    with open("tests/zeroex/data.json", "r") as f:
        data = json.load(f)
    return data[testName]

def save_test_data(testName, blockNumber, params):
    with open("tests/zeroex/data.json", "r") as f:
        data = json.load(f)
    data[testName]["blockNumber"] = blockNumber
    data[testName]["params"] = params
    with open("tests/zeroex/data.json", "w") as f:
        json.dump(data, f, indent=4)    

# https://api.0x.org/swap/v1/quote?sellToken=0xba100000625a3754423978a60c9317c58a424e3D&buyToken=ETH&sellAmount=24409825087058625000&slippagePercentage=0.3

def fetch_0x_data(sellToken, buyToken, sellAmount, slippagePercentage):
    resp = requests.get("https://api.0x.org/swap/v1/quote", {
        "sellToken": sellToken,
        "buyToken": buyToken,
        "sellAmount": sellAmount,
        "slippagePercentage": slippagePercentage
    })
    return resp.json()["data"]