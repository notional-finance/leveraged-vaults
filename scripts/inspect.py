# flake8: noqa
import json
from brownie import network, interface
from brownie.network.contract import Contract

def get_router_args(router):
    return [
        router.GOVERNANCE(),
        router.VIEWS(),
        router.INITIALIZE_MARKET(),
        router.NTOKEN_ACTIONS(),
        router.BATCH_ACTION(),
        router.ACCOUNT_ACTION(),
        router.ERC1155(),
        router.LIQUIDATE_CURRENCY(),
        router.LIQUIDATE_FCASH(),
        router.TREASURY(),
        router.CALCULATION_VIEWS(),
        router.VAULT_ACCOUNT_ACTION(),
        router.VAULT_ACTION(),
        router.VAULT_LIQUIDATION_ACTION(),
        router.VAULT_ACCOUNT_HEALTH(),
    ]

def get_addresses():
    networkName = network.show_active()
    if networkName == "mainnet-fork" or networkName == "mainnet-current" or networkName == "mainnet":
        networkName = "mainnet"
    if networkName == "arbitrum-fork" or networkName == "arbitrum-current":
        networkName = "arbitrum-one"
    output_file = "v3.{}.json".format(networkName)
    addresses = None
    with open(output_file, "r") as f:
        addresses = json.load(f)

    notional = Contract.from_abi("Notional", addresses["notional"], abi=interface.NotionalProxy.abi)
    tradingModule = Contract.from_abi("TradingModule", addresses["tradingModule"], abi=interface.ITradingModule.abi)

    return (addresses, notional, networkName, tradingModule)

def main():
    (addresses, notional, networkName, tradingModule) = get_addresses()