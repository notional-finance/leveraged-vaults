import json
import yaml
import shutil
import os
from jinja2 import Template
from tests.config import *

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

def get_token_permissions(network, tokens):
    return [{
        "dexId": DexIds[t['dex']],
        "tradeTypeFlags": t['tradeTypeFlags'],
        "tokenAddress": token[network][t['token']],
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

    for test in tests[network]:
        # test['settings'] = { **defaults['settings'], **test['settings'] } if 'settings' in test else defaults['settings']
        test['setUp'] = { **defaults['setUp'], **test['setUp'] } if 'setUp' in test else defaults['setUp']
        test['config'] = { **defaults['config'], **test['config'] } if 'config' in test else defaults['config']

        # Look up the existing deployment from the json registry
        fileName = f"PendlePT_{test['stakeSymbol']}_{test['expiry']}_{test['primaryBorrowCurrency']}"
        poolName = "[{}]:{}_{}".format(test['primaryBorrowCurrency'], test['stakeSymbol'], test['expiry'])
        try:
            test['existingDeployment'] = vaults[network]["Pendle"][poolName]
        except:
            pass
        test['primaryDexId'] = DexIds[test['primaryDex']]
        test['exchangeCode'] = get_exchange_data(test['primaryDex'], test['exchangeData'])
        test['oracles'] = get_oracles(network, test['oracles'])
        test['rewards'] = get_tokens(network, test['rewards']) if 'rewards' in test else []
        test['permissions'] = get_token_permissions(network, test['permissions']) if 'permissions' in test else []
        test['borrowCurrencyId'] = currencyIds[network][test['primaryBorrowCurrency']]
        test['borrowToken'] = token[network][test['primaryBorrowCurrency']]
        test['stakeToken'] = token[network][test['stakeSymbol']]
        test['baseToUSDOracle'] = oracle[network][test['stakeSymbol']]

        output = render_template(template, test)
        output_file = f"{output_dir}/{fileName}.t.sol"  # Define the output file name
        with open(output_file, 'w') as f:
            f.write(output)

if __name__ == "__main__":
    yaml_file = "tests/Staking/PendlePTTests.yml"
    template_file = "tests/Staking/PendlePT.t.sol.j2"
    generate_files('arbitrum', yaml_file, template_file)
    generate_files('mainnet', yaml_file, template_file)
