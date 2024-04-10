import json
import yaml
import shutil
import os
from jinja2 import Template

currencyIds = {
    "mainnet": {
        "ETH": 1,
        "DAI": 2,
        "USDC": 3,
        "WBTC": 4,
        "wstETH": 5,
        "FRAX": 6,
        "rETH": 7,
        "USDT": 8,
        "sDAI": 9,
    },
    "arbitrum": {
        "ETH": 1,
        "DAI": 2,
        "USDC": 3,
        "WBTC": 4,
        "wstETH": 5,
        "FRAX": 6,
        "rETH": 7,
        "USDT": 8,
        "CBETH": 9,
        "GMX": 10,
        "ARB": 11,
        "RDNT": 12,
    }
}

token = {
    "mainnet": {
        "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        "ETH": "0x0000000000000000000000000000000000000000",
        "DAI": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        "USDC": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        "WBTC": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
        "wstETH": "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
        "FRAX": "0x853d955aCEf822Db058eb8505911ED77F175b99e",
        "rETH": "0xae78736Cd615f374D3085123A210448E74Fc6393",
        "USDT": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        "cbETH": "0xBe9895146f7AF43049ca1c1AE358B0541Ea49704",
        "BAL": "0xba100000625a3754423978a60c9317c58a424e3D",
        "AURA": "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF",
        "CRV": "0xD533a949740bb3306d119CC777fa900bA034cd52",
        "crvUSD": "0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E",
        "pyUSD": "0x6c3ea9036406852006290770BEdFcAbA0e23A0e8",
        "osETH": "0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38",
        "weETH": "0xE47F6c47DE1F1D93d8da32309D4dB90acDadeEaE",
        "GHO": "0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f",
        'CVX': "0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B",
        'SWISE': "0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2",
        'ezETH': "0xE1fFDC18BE251E76Fb0A1cBfA6d30692c374C5fc"
    },
    "arbitrum": {
        "WETH": "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        "ETH": "0x0000000000000000000000000000000000000000",
        "DAI": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
        "USDC": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
        "USDC_e": "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        "WBTC": "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
        "wstETH": "0x5979D7b546E38E414F7E9822514be443A4800529",
        "FRAX": "0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F",
        "rETH": "0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8",
        "USDT": "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
        "cbETH": "0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f",
        "GMX": "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
        "ARB": "0x912CE59144191C1204E64559FE8253a0e49E6548",
        "RDNT": "0x3082CC23568eA640225c2467653dB90e9250AaA0",
        "BAL": "0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8",
        "AURA": "0x1509706a6c66CA549ff0cB464de88231DDBe213B",
        "CRV": "0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978",
        "crvUSD": "0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5"
    }
}

"""
To read the most recent oracles from the blockchain:
Load in brownie:
m = TradingModule.at(...)
tokens = { "ETH": 0x000.. }
{ name: m.priceOracles(address)['oracle'] for (name, address) in tokens.items() }
"""
oracle = {
    "mainnet": {
        'BAL': "0xdF2917806E30300537aEB49A7663062F4d1F2b5F",
        'DAI': "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9",
        'ETH': "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
        'USDC': "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
        'USDT': "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D",
        'WBTC': "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
        'WETH': "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
        'wstETH': "0x8770d8dEb4Bc923bf929cd260280B5F1dd69564D",
        'FRAX': "0x0000000000000000000000000000000000000000",
        'CRV': "0x0000000000000000000000000000000000000000",
        'AURA': "0x0000000000000000000000000000000000000000",
        'cbETH': "0x0000000000000000000000000000000000000000",
        'rETH': "0xA7D273951861CF07Df8B0A1C3c934FD41bA9E8Eb",
        'crvUSD': "0xEEf0C605546958c1f899b6fB336C20671f9cD49F",
        'pyUSD': "0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1",
        'osETH': "0x3d3d7d124B0B80674730e0D31004790559209DEb",
        'weETH': "0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136",
        'GHO': "0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC",
        'ezETH': "0xCa140AE5a361b7434A729dCadA0ea60a50e249dd"
    },
    "arbitrum": {
        "WETH": "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
        "ETH": "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
        "DAI": "0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB",
        "USDC": "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
        "USDC_e": "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
        "WBTC": "0x6ce185860a4963106506C203335A2910413708e9",
        "wstETH": "0x29aFB1043eD699A89ca0F0942ED6F6f65E794A3d",
        "FRAX": "0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8",
        "rETH": "0x40cf45dBD4813be545CF3E103eF7ef531eac7283",
        "USDT": "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
        "cbETH": "0x4763672dEa3bF087929d5537B6BAfeB8e6938F46",
        "RDNT": "0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352",
        "crvUSD": "0x0a32255dd4BB6177C994bAAc73E0606fDD568f66"
    }
}

networks = ['arbitrum', 'mainnet']

def get_contract_name(test):
    return test['vaultName'] \
        .replace(".", "_") \
        .replace(":", "_") \
        .replace('/', '_') \
        .replace('[', 'x') \
        .replace(']', '')

def get_oracles(network, oracles):
    return [{
        "symbol": o,
        "tokenAddress": token[network][o],
        "oracleAddress": oracle[network][o]
    } for o in oracles]

def get_tokens(network, tokens):
    return [{
        "symbol": t,
        "tokenAddress": token[network][t],
    } for t in tokens]

def render_template(template, data):
    template = Template(template)
    return template.render(data)

def generate_files(network, yaml_file, template_file):
    output_dir = f"./tests/generated/{network}"
    with open(yaml_file, 'r') as f:
        tests = yaml.safe_load(f)

    with open(template_file, 'r') as f:
        template = f.read()

    with open("vaults.json", 'r') as f:
        vaults = json.load(f)

    # Get defaults
    defaults = tests['defaults']

    # Remove all files in the directory
    shutil.rmtree(output_dir, ignore_errors=True)
    os.makedirs(output_dir)

    for test in tests[network]:
        test['settings'] = { **defaults['settings'], **test['settings'] } if 'settings' in test else defaults['settings']
        test['setUp'] = { **defaults['setUp'], **test['setUp'] } if 'setUp' in test else defaults['setUp']
        test['config'] = { **defaults['config'], **test['config'] } if 'config' in test else defaults['config']
        test['contractName'] = get_contract_name(test)

        # Look up the existing deployment from the json registry
        [_, protocol, poolName] = test['contractName'].split("_", 2)
        poolName = "[{}]:{}".format(test['primaryBorrowCurrency'], poolName)
        try:
            test['existingDeployment'] = vaults[network][protocol][poolName]
        except:
            pass
        test['oracles'] = get_oracles(network, test['oracles'])
        test['rewards'] = get_tokens(network, test['rewards']) if 'rewards' in test else []
        test['primaryBorrowCurrency'] = currencyIds[network][test['primaryBorrowCurrency']]

        output = render_template(template, test)
        output_file = f"{output_dir}/{test['contractName']}.t.sol"  # Define the output file name
        with open(output_file, 'w') as f:
            f.write(output)

if __name__ == "__main__":
    yaml_file = "tests/SingleSidedLP/SingleSidedLPTests.yml"
    template_file = "tests/SingleSidedLP/SingleSidedLP.t.sol.j2"
    generate_files('arbitrum', yaml_file, template_file)
    generate_files('mainnet', yaml_file, template_file)
