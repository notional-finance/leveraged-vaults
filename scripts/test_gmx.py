
from brownie import accounts, ZERO_ADDRESS, Wei, Contract, interface, GmxFundingVault, nProxy
from scripts.common import get_deposit_params

def main():
    deployer = accounts.load("MAINNET_DEPLOYER")
    notional = interface.NotionalProxy("0x1344A36A1B56144C3Bc62E7757377D288fDE0369")

    whale = accounts.at("0x3DD1D15b3c78d6aCFD75a254e857Cbe5b9fF0aF2", force=True)
    usdc = interface.IERC20("0xaf88d065e77c8cC2239327C5EDb3A432268e5831")

    impl = GmxFundingVault.deploy(notional, [
        1, 
        "0xaf88d065e77c8cc2239327c5edb3a432268e5831",  # collateral token
        "0x7c68c7866a64fa2160f78eeae12217ffbf871fa8",  # gmx router
        "0x70d95587d40a2caf56bd97485ab3eec10bee6336",  # gmx market
        "0xf60becbba223eea9495da3f606753867ec10d139",  # gmx reader
        "0x31ef83a530fde1b38ee9a18093a333d8bbbc40d5",  # order vault
        "0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8"   # trading module
    ], {
        "from": deployer
    })

    proxy = nProxy.deploy(impl.address, bytes(0), {"from": deployer})
    proxy = Contract.from_abi("GmxFundingVault", proxy.address, GmxFundingVault.abi)

    proxy.initialize([
        "GMX Funding Vault", 
        1,
        [
            Wei(2e6),   # 2%
            Wei(1e3),   # 10%
            100,        # 1%
            9950        # 0.5%
        ] 
    ], {"from": notional.owner()})

    accounts[0].transfer(proxy.address, 1e18)
    usdc.transfer(proxy.address, 100e6, {"from": whale})

    print(proxy.depositFromNotional.call(ZERO_ADDRESS, 0, 0, get_deposit_params(), {"from": notional.address}))
    proxy.depositFromNotional(ZERO_ADDRESS, 0, 0, get_deposit_params(), {"from": notional.address})