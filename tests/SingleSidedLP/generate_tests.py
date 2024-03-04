import yaml
import shutil
import os
from jinja2 import Template

token = {
    "mainnet": {
        "WETH": "",
        "ETH": "0x0000000000000000000000000000000000000000",
        "DAI": "",
        "USDC": "",
        "USDC_e": "",
        "WBTC": "",
        "wstETH": "",
        "FRAX": "",
        "rETH": "",
        "USDT": "",
        "cbETH": "",
        "BAL": "",
        "AURA": "",
        "CRV": ""
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
        "CRV": "0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978"
    }
}

# TODO: can we just read this from the trading module?
oracle = {
    "mainnet": {

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
        "RDNT": "0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352"
    }
}

networks = ['arbitrum', 'mainnet']

def get_contract_name(test):
    return 'Test_' + test['vaultName'] \
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

def render_template(template, data):
    template = Template(template)
    return template.render(data)

def generate_files(network, yaml_file, template_file):
    output_dir = f"./tests/generated/{network}"
    with open(yaml_file, 'r') as f:
        tests = yaml.safe_load(f)

    with open(template_file, 'r') as f:
        template = f.read()

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
        test['oracles'] = get_oracles(network, test['oracles'])

        output = render_template(template, test)
        output_file = f"{output_dir}/{test['contractName']}.t.sol"  # Define the output file name
        with open(output_file, 'w') as f:
            f.write(output)

if __name__ == "__main__":
    yaml_file = "tests/SingleSidedLP/SingleSidedLPTests.yml"
    template_file = "tests/SingleSidedLP/SingleSidedLP.t.sol.j2"
    generate_files('arbitrum', yaml_file, template_file)
    # generate_files('mainnet', yaml_file, template_file)
