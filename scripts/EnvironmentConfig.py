import json
from brownie import (
    ZERO_ADDRESS,
    accounts, 
    interface,
    TradingModule,
    nProxy,
    EmptyProxy,
    WstETHChainlinkOracle,
    BalancerPoolChainlinkAdapter,
    ChainlinkAdapter,
    AaveFlashLiquidator
)
from brownie.network.contract import Contract
from brownie.network.state import Chain
from scripts.common import deployArtifact

chain = Chain()

with open("abi/nComptroller.json", "r") as a:
    Comptroller = json.load(a)

with open("abi/nCErc20.json") as a:
    cToken = json.load(a)

with open("abi/nCEther.json") as a:
    cEther = json.load(a)

with open("abi/ERC20.json") as a:
    ERC20ABI = json.load(a)

with open("abi/Notional.json") as a:
    NotionalABI = json.load(a)

networks = {}

with open("v2.mainnet.json", "r") as f:
    networks["mainnet"] = json.load(f)

with open("v2.goerli.json", "r") as f:
    networks["goerli"] = json.load(f)

with open("v3.arbitrum-one.json", "r") as f:
    networks["arbitrum"] = json.load(f)

class Environment:
    def __init__(self, network) -> None:
        self.forkBlockNumber = chain.height
        self.network = network
        addresses = networks[network]
        self.addresses = addresses
        self.deployer = accounts.at(addresses["deployer"], force=True)
        self.notional = Contract.from_abi(
            "Notional", addresses["notional"], NotionalABI
        )

        self.tokens = {}
        for (symbol, obj) in addresses["tokens"].items():
            if symbol.startswith("c"):
                self.tokens[symbol] = Contract.from_abi(symbol, obj, cToken["abi"])
            else:
                self.tokens[symbol] = Contract.from_abi(symbol, obj, ERC20ABI)

        self.whales = {}
        for (name, addr) in addresses["whales"].items():
            self.whales[name] = accounts.at(addr, force=True)

        self.owner = accounts.at(self.notional.owner(), force=True)
        self.balancerVault = interface.IBalancerVault(addresses["balancer"]["vault"])
        self.aaveLiquidator = self.deployAaveLiquidator()

        self.deployTradingModule()

    def deployAaveLiquidator(self):
        liquidator = AaveFlashLiquidator.deploy(
            self.notional,
            "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
            {"from": self.deployer}            
        )
        liquidator.enableCurrencies([1, 2, 3, 4], {"from": self.deployer})
        return liquidator

    def deployTradingModule(self, useFresh=False):
        if useFresh == False:
            self.tradingModule = Contract.from_abi("TradingModule", self.addresses["trading"]["proxy"], TradingModule.abi)
            impl = TradingModule.deploy(self.notional.address, self.tradingModule.address, {"from": self.deployer})
            self.tradingModule.upgradeTo(impl.address, {"from": "0xe6fb62c2218fd9e3c948f0549a2959b509a293c8"})
        else:
            emptyImpl = EmptyProxy.deploy({"from": self.deployer})
            self.proxy = nProxy.deploy(emptyImpl.address, bytes(), {"from": self.deployer})

            impl = TradingModule.deploy(self.notional.address, self.proxy.address, {"from": self.deployer})
            emptyProxy = Contract.from_abi("EmptyProxy", self.proxy.address, EmptyProxy.abi)
            emptyProxy.upgradeTo(impl.address, {"from": self.deployer})

            self.tradingModule = Contract.from_abi("TradingModule", self.proxy.address, TradingModule.abi)

            self.tradingModule.initialize(3600 * 24, {"from": self.notional.owner()})

            # ETH/USD oracle
            self.tradingModule.setPriceOracle(
                ZERO_ADDRESS, 
                "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419", 
                {"from": self.notional.owner()}
            )

            # WETH/USD oracle
            self.tradingModule.setPriceOracle(
                self.tokens["WETH"].address, 
                "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419", 
                {"from": self.notional.owner()}
            )
            # DAI/USD oracle
            self.tradingModule.setPriceOracle(
                self.tokens["DAI"].address,
                "0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9",
                {"from": self.notional.owner()}
            )
            # USDC/USD oracle
            self.tradingModule.setPriceOracle(
                self.tokens["USDC"].address,
                "0x8fffffd4afb6115b954bd326cbe7b4ba576818f6",
                {"from": self.notional.owner()}
            )
            # USDT/USD oracle
            self.tradingModule.setPriceOracle(
                self.tokens["USDT"].address,
                "0x3e7d1eab13ad0104d2750b8863b489d65364e32d",
                {"from": self.notional.owner()}
            )
            # WBTC/USD oracle
            self.tradingModule.setPriceOracle(
                self.tokens["WBTC"].address,
                "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
                {"from": self.notional.owner()}
            )
            # BAL/USD oracle
            self.tradingModule.setPriceOracle(
                self.tokens["BAL"].address,
                "0xdf2917806e30300537aeb49a7663062f4d1f2b5f",
                {"from": self.notional.owner()}
            )
            # stETH/USD oracle
            self.tradingModule.setPriceOracle(
                self.tokens["stETH"].address,
                "0xcfe54b5cd566ab89272946f602d76ea879cab4a8",
                {"from": self.notional.owner()}
            )
            # wstETH/USD oracle
            wstETHAdapater = WstETHChainlinkOracle.deploy(
                "0xcfe54b5cd566ab89272946f602d76ea879cab4a8",
                self.tokens["wstETH"].address,
                {"from": self.notional.owner()}
            )
            self.tradingModule.setPriceOracle(
                self.tokens["wstETH"].address,
                wstETHAdapater.address,
                {"from": self.notional.owner()}
            )
            # AURA/USD oracle
            auraETHAdapter = BalancerPoolChainlinkAdapter.deploy(
                self.notional,
                "0xc29562b045d80fd77c69bec09541f5c16fe20d9d", 
                "AURA/ETH Chainlink Adapter", 
                3600,
                True,
                {"from": self.notional.owner()}    
            )
            auraUSDAdapter = ChainlinkAdapter.deploy(
                "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",
                auraETHAdapter.address,
                "AURA/USD Chainlink Adapter",
                {"from": self.notional.owner()}
            )
            self.tradingModule.setPriceOracle(
                self.tokens["AURA"].address,
                auraUSDAdapter.address,
                {"from": self.notional.owner()}
            )        


def getEnvironment(network = "mainnet"):
    if network == "mainnet-fork" or network == "hardhat-fork":
        network = "mainnet"
    return Environment(network)

