import json
from . import get_addresses
from brownie import EmptyProxy, nProxy, accounts, TradingModule, Contract


def main():
    [networkName, addresses] = get_addresses()
    deployer = accounts.load(networkName.upper() + "_DEPLOYER")
    emptyImpl = EmptyProxy.deploy({"from": deployer})
    proxy = nProxy.deploy(emptyImpl.address, bytes(), {"from": deployer})

    impl = TradingModule.deploy(addresses['notional'], proxy.address, {"from": deployer})
    emptyProxy = Contract.from_abi("EmptyProxy", proxy.address, EmptyProxy.abi)
    emptyProxy.upgradeTo(impl.address, {"from": deployer})

    print("Trading Module Deployed To: ", proxy.address)

    tradingModule = Contract.from_abi("TradingModule", proxy.address, TradingModule.abi)