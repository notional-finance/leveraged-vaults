import eth_abi
from brownie import (
    ZERO_ADDRESS,
    BalancerV2Adapter,
    CurveAdapter,
    NotionalVaultAdapter,
    UniV2Adapter,
    UniV3Adapter,
    ZeroExAdapter,
    nProxy,
    TradingModule,
    MockNotionalVault,
    MockAggregator,
    accounts,
    interface,
    Contract
)
from brownie.network.state import Chain
from brownie.convert import to_bytes

chain = Chain()

DexId = {
    "UNISWAP_V2": 1,
    "UNISWAP_V3": 2,
    "ZERO_EX": 3,
    "BALANCER_V2": 4,
    "CURVE": 5,
    "NOTIONAL_VAULT": 6
}

TradeType = {
    "EXACT_IN_SINGLE": 0,
    "EXACT_OUT_SINGLE": 1,
    "EXACT_IN_BATCH": 2,
    "EXACT_OUT_BATCH": 3
}

EnvironmentConfig = {
    "BalancerVault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    "UniV2Router": "0xE592427A0AEce92De3Edee1F18E0157C05861564",
    "UniV3Router": "0xE592427A0AEce92De3Edee1F18E0157C05861564",
    "ZeroExExchange": "0xdef1c0ded9bec7f1a1670819833240f027b25eff",
    "Notional": "0x1344A36A1B56144C3Bc62E7757377D288fDE0369",
    "CurveRegistryProvider": "0x0000000022d53366457f9d5e68ec105046fc4383",
    "CurveRouter": "0xfA9a30350048B2BF66865ee20363067c66f67e58",
    "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "DAI": "0x6b175474e89094c44da98b954eedeac495271d0f",
    "USDC": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    "stETH": "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
}

class TestAccounts:
    def __init__(self) -> None:
        self.ETHWhale = accounts.at("0x9acb5CE4878144a74eEeDEda54c675AA59E0D3D2", force=True)
        self.stETHWhale = accounts.at("0x6Cf9AA65EBaD7028536E353393630e2340ca6049", force=True)
        self.DAIWhale = accounts.at("0x6dfaf865a93d3b0b5cfd1b4db192d1505676645b", force=True)

class Environment:
    def __init__(self, deployer) -> None:
        self.curveAdapter = CurveAdapter.deploy(
            EnvironmentConfig["CurveRegistryProvider"],
            EnvironmentConfig["CurveRouter"],
            EnvironmentConfig["WETH"],
            {"from": deployer}
        )

        self.balancerV2Adapter = BalancerV2Adapter.deploy(EnvironmentConfig["BalancerVault"], {"from": deployer})
        self.uniV2Adapter = UniV2Adapter.deploy(EnvironmentConfig["UniV2Router"], {"from": deployer})
        self.uniV3Adapter = UniV3Adapter.deploy(EnvironmentConfig["UniV3Router"], {"from": deployer})
        self.zeroExAdapter = ZeroExAdapter.deploy(EnvironmentConfig["ZeroExExchange"], {"from": deployer})
        self.notionalVaultAdapter = NotionalVaultAdapter.deploy({"from": deployer})

        impl = TradingModule.deploy(
            self.uniV2Adapter.address,
            self.uniV3Adapter.address,
            self.balancerV2Adapter.address,
            self.curveAdapter.address,
            self.zeroExAdapter.address,
            self.notionalVaultAdapter.address,
            {"from": deployer}
        )

        initData = impl.initialize.encode_input(deployer.address)
        self.proxy = nProxy.deploy(impl.address, initData, {"from": deployer})
        self.trading = Contract.from_abi("TradingModule", self.proxy.address, interface.ITradingModule.abi)

        self.mockAggregator = MockAggregator.deploy(18, {"from": deployer})
        self.mockAggregator.setAnswer(1e18, {"from": deployer})
        self.mockVault = MockNotionalVault.deploy(
            self.proxy.address, 
            self.mockAggregator.address,
            EnvironmentConfig["WETH"],
            EnvironmentConfig["DAI"],
            ZERO_ADDRESS,
            {"from": deployer}
        )

        # ETH/USD oracle
        self.trading.setPriceOracle(
            "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 
            "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419", 
            {"from": deployer}
        )
        # DAI/USD oracle
        self.trading.setPriceOracle(
            "0x6B175474E89094C44Da98b954EedeAC495271d0F",
            "0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9",
            {"from": deployer}
        )
        # USDC/USD oracle
        self.trading.setPriceOracle(
            "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            "0x8fffffd4afb6115b954bd326cbe7b4ba576818f6",
            {"from": deployer}
        )
        # WBTC/USD oracle
        self.trading.setPriceOracle(
            "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
            "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
            {"from": deployer}
        )

def main():
    testAccounts = TestAccounts()
    deployer = accounts.load("MAINNET_DEPLOYER")
    env = Environment(deployer)
