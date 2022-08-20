from . import get_addresses
from brownie import CrossCurrencyfCashVault, nProxy, accounts

def main():
    [networkName, addresses] = get_addresses()
    deployer = accounts.load(networkName.upper() + "_DEPLOYER")

    impl = CrossCurrencyfCashVault.at("0x1b2247E2b4A94bde3DFFa01C52c3b178BFAE2C2b")

    initializeCallData = impl.initialize.encode_input(
        "Cross Currency fCash: DAI/USDC",
        2, 3, 0.995e18
    )
    proxy = nProxy.deploy(impl.address, initializeCallData, {"from": deployer})
