
import json
import eth_abi
from brownie import accounts, ZERO_ADDRESS, Wei, Contract, interface, GmxFundingVault, nProxy
from brownie.network.state import Chain
from scripts.common import get_deposit_params

chain = Chain()

def main():
    deployer = accounts.load("MAINNET_DEPLOYER")
    notional = interface.NotionalProxy("0x1344A36A1B56144C3Bc62E7757377D288fDE0369")

    whale = accounts.at("0x3DD1D15b3c78d6aCFD75a254e857Cbe5b9fF0aF2", force=True)
    usdc = interface.IERC20("0xaf88d065e77c8cC2239327C5EDb3A432268e5831")

    ctorParams = [
        1, 
        "0xaf88d065e77c8cc2239327c5edb3a432268e5831",  # collateral token
        "0x7c68c7866a64fa2160f78eeae12217ffbf871fa8",  # gmx router
        "0x70d95587d40a2caf56bd97485ab3eec10bee6336",  # gmx market
        "0xf60becbba223eea9495da3f606753867ec10d139",  # gmx reader
        "0x31ef83a530fde1b38ee9a18093a333d8bbbc40d5",  # order vault
        "0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8"   # trading module
    ]

    print(eth_abi.encode(["address","(uint16,address,address,address,address,address,address)"],[notional.address,ctorParams]).hex())

    impl = GmxFundingVault.deploy(notional, ctorParams, {
        "from": deployer
    })

    proxy = nProxy.deploy(impl.address, bytes(0), {"from": deployer})
    proxy = Contract.from_abi("GmxFundingVault", proxy.address, GmxFundingVault.abi)

    initParams = [
        "GMX Funding Vault", 
        1,
        [
            Wei(2e6),   # 2%
            Wei(1e3),   # 10%
            100,        # 1%
            9950        # 0.5%
        ] 
    ]

    proxy.initialize(initParams, {"from": notional.owner()})

    accounts[0].transfer(proxy.address, 1e18)
    usdc.transfer(proxy.address, 100e6, {"from": whale})

    print(proxy.depositFromNotional.call(ZERO_ADDRESS, 0, 0, get_deposit_params(), {"from": notional.address}))

    chain.mine(4)

    proxy.depositFromNotional(ZERO_ADDRESS, 0, 0, get_deposit_params(), {"from": notional.address})

    with open("abi/GmxOrderHandler.json", "r") as f:
        abi = json.load(f)

    orderHandler = Contract.from_abi("OrderHandler", "0x352f684ab9e97a6321a13CF03A61316B681D9fD2", abi)
    keeper = accounts.at("0xc539cb358a58ac67185baad4d5e3f7fcfc903700", force=True)

    orderHash = proxy.getStrategyContext()["gmxState"]["orderHash"]
    executionParams = [
        "0", # "signerInfo"
        [],  # "tokens"
        [],  # "compactedMinOracleBlockNumbers"
        [],  # "compactedMaxOracleBlockNumbers"
        [],  # "compactedOracleTimestamps"
        [],  # "compactedDecimals"
        [],  # "compactedMinPrices"
        [],  # "compactedMinPricesIndexes"
        [],  # "compactedMaxPrices"
        [],  # "compactedMaxPricesIndexes"
        [],  # "signatures"
        [],  # "priceFeedTokens"
        [
            "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
            "0xaf88d065e77c8cc2239327c5edb3a432268e5831"
        ],  # "realtimeFeedTokens"
        [
            "0x000637558ae605b87120ff75c52308703f79ebafba207a65d69705ec7ba8beb70000000000000000000000000000000000000000000000000000000001515304000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002c00000010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012074aca63821bf7ead199e924d261d277cbec96d1026ab65267d655c51b453691400000000000000000000000000000000000000000000000000000000651bb77500000000000000000000000000000000000000000000000000000026dc28b97200000000000000000000000000000000000000000000000000000026dc21185200000000000000000000000000000000000000000000000000000026dc305a9200000000000000000000000000000000000000000000000000000000082aa5568969ef93c6940a0fb65632907634100136e8bc3fefa2089707545ef2a91c9c7100000000000000000000000000000000000000000000000000000000082aa55600000000000000000000000000000000000000000000000000000000651bb77500000000000000000000000000000000000000000000000000000000000000043cdb286aa8c78a6b66352d2740e5b148a2a7115d1eaef07bca0736fcc73c6ac35ed83581f621c1cbf95a1d609411c90be094bf83cac66a004fd249fdebef59d7216544f0444ac0426249987240aaf8d31b709395113f1ea17e4ffda88f5798ae84e28883b81b0055429a902826d745d584969d79f2f583760a9d76a2dafebbe80000000000000000000000000000000000000000000000000000000000000004674011523def961f63dbfbfd5101d2777cd94b5699b4684dd91c20db7ed865bd765574f793592cb9398c8f521eb9a0a91466e417b8af46dea0c677602a27eeff3de0502260bbf162d1a55e7539f809a44e7d385d0db4a4525ec4a30a1746ef5322be8da9a50e888e8ac86851c4454948549a6422c1fa472fcc4d06da112e1b7b",
            "0x000636e8260d36292bcbc2d205dc922cde2a93a929350b7163c803ac4fd89560000000000000000000000000000000000000000000000000000000000151ca05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002c00101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012095241f154d34539741b19ce4bae815473fd1b2a90ac3b4b023a692f31edfe90e00000000000000000000000000000000000000000000000000000000651bb7750000000000000000000000000000000000000000000000000000000005f5b4d50000000000000000000000000000000000000000000000000000000005f592e00000000000000000000000000000000000000000000000000000000005f5cc9900000000000000000000000000000000000000000000000000000000082aa5568969ef93c6940a0fb65632907634100136e8bc3fefa2089707545ef2a91c9c7100000000000000000000000000000000000000000000000000000000082aa55600000000000000000000000000000000000000000000000000000000651bb7750000000000000000000000000000000000000000000000000000000000000004c4ef2f175efbbe66e86befc269a6462845be1f77732e3647f10b3bd90af4c4ea209ae96f70dd3c3eedc2e41510412b5af0f8df744425b0873474eef726b26fb2a028f496e158c6526c4beabdea8913b8651f113ee816ae9e0244d5895a6118e5d368dfbb7a9cc329dd356f86b22dbb6a17ab7c76ac663e558f73982835840cef00000000000000000000000000000000000000000000000000000000000000042fc585b995d2bd85096fdc8b77181f2036931c0de0497b489360f478b170988453ba7555df4ad61ef2a14272c6f29a3079981e95543110b8c2db35e19e33f18f2632cf609af8d48c7acd26d9a86a3332feb0348c4f0413d7609bdf8d0983b6ae253de38b49ca32cc9a0ec7102daaf73a10155d4ad4eb36c11e495cdc0da6321f"
        ]  # "realtimeFeedData"
    ]

    chain.mine(25)

    # orderHandler.executeOrder.call(orderHash, executionParams, {"from": keeper})

