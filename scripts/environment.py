from brownie import (
    ZERO_ADDRESS,
    accounts, 
    network,
    interface,
    Contract,
    Balancer2TokenVault,
    BalancerBoostController,
    TradingModule,
    BalancerV2Adapter,
    nProxy,
    MockDelegateRegistry
)
from eth_utils import keccak
from scripts.trading.environment import Environment as TradingEnvironment
from scripts.common import deployArtifact

EnvironmentConfig = {
    "goerli": {
        "notional": "0xD8229B55bD73c61D840d339491219ec6Fa667B0a",
        "balancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        "balancerMinter": "0xdf0399539A72E2689B8B2DD53C3C2A0883879fDd",
        "ETHNOTEPool": {
            "id": "0xde148e6cc3f6047eed6e97238d341a2b8589e19e000200000000000000000053",
            "address": "0xdE148e6cC3F6047EeD6E97238D341A2b8589e19E",
            "liquidityGauge": ZERO_ADDRESS
        },
        "BALETHPool": {
            "address": ZERO_ADDRESS # Not used on goerli
        },
        "veToken": "0x33A99Dcc4C85C014cf12626959111D5898bbCAbF",
        "feeDistributor": "0x7F91dcdE02F72b478Dc73cB21730cAcA907c8c44",
        "gaugeController": "0xBB1CE49b16d55A1f2c6e88102f32144C7334B116",
        "sNOTE": "0x9AcDB8100Aa74913f7702bf8b43128f36E6e3f22",
        "WETH": "0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1"
    },
    "mainnet": {
        "notional": "0x1344A36A1B56144C3Bc62E7757377D288fDE0369",
        "balancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        "balancerMinter": "0x239e55F427D44C3cc793f49bFB507ebe76638a2b",
        "ETHUSDCPool": {
            "id": "0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
            "address": "0x96646936b91d6B9D7D0c47C496AfBF3D6ec7B6f8",
            "liquidityGauge": "0x9ab7b0c7b154f626451c9e8a68dc04f58fb6e5ce",
        },
        "ETHNOTEPool": {
            "id": "0x5122e01d819e58bb2e22528c0d68d310f0aa6fd7000200000000000000000163",
            "address": "0x5122e01d819e58bb2e22528c0d68d310f0aa6fd7",
            "liquidityGauge": "0x40ac67ea5bd1215d99244651cc71a03468bce6c0",
        },
        "BALETHPool": {
            "address": "0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56"
        },
        "veToken": "0xC128a9954e6c874eA3d62ce62B468bA073093F25",
        "feeDistributor": "0x26743984e3357eFC59f2fd6C1aFDC310335a61c9",
        "gaugeController": "0xC128468b7Ce63eA702C1f104D55A2566b13D3ABD",
        "sNOTE": "0x38DE42F4BA8a35056b33A746A6b45bE9B1c3B9d2",
        "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        "delegateRegistry": "0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446"
    }
}

class Environment:
    def __init__(self, config, deployer) -> None:
        self.config = config
        self.notional = interface.NotionalProxy(config["notional"])
        self.notional.upgradeTo('0x433a0679756D6EB110E8Ff730d06DBee5D9F5db5', {'from': self.notional.owner()})
        self.balancerV2Adapter = BalancerV2Adapter.deploy(config["balancerVault"], {"from": deployer})
        impl = TradingModule.deploy(
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            self.balancerV2Adapter.address,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            ZERO_ADDRESS,            
            {"from": deployer}
        )

        initData = impl.initialize.encode_input(deployer.address)
        self.proxy = nProxy.deploy(impl.address, initData, {"from": deployer})
        self.tradingModule = Contract.from_abi("TradingModule", self.proxy.address, interface.ITradingModule.abi)

        self.mockDelegateRegistry = MockDelegateRegistry.deploy({"from": deployer})

        # Deploy balancer test pool
        veBalDelegator = deployArtifact(
            "scripts/artifacts/VeBalDelegator.json",
            [
                config["BALETHPool"]["address"],
                config["veToken"],
                config["feeDistributor"],
                config["balancerMinter"],
                config["gaugeController"],
                config["sNOTE"],
                self.mockDelegateRegistry.address,
                keccak(text="balancer.eth"),
                deployer.address
            ],
            deployer,
            "VeBalDelegator"
        )

        boostController = BalancerBoostController.deploy(
            veBalDelegator.address,
            config["notional"],
            {"from": deployer}
        )

        Balancer2TokenVault.deploy(
            config["notional"],
            1, # ETH
            True,
            True,
            [
                config["WETH"],
                config["balancerVault"],
                config["ETHNOTEPool"]["id"],
                boostController.address,
                config["ETHNOTEPool"]["liquidityGauge"],
                self.tradingModule.address,
                3600,
                3600 * 24 * 7,
                0.2e8,
                3600 * 6
            ],
            {"from": deployer}
        )

def main():
    networkName = network.show_active()
    if networkName == "hardhat-fork":
        networkName = "mainnet"
    elif networkName == "hardhat-fork-goerli":
        networkName = "goerli"
    deployer = accounts.load(networkName.upper() + "_DEPLOYER")
    env = Environment(EnvironmentConfig[networkName], deployer)