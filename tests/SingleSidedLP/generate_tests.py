import json
import yaml
import shutil
import os
from jinja2 import Template
import sys
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
