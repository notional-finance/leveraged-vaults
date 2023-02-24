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
    ChainlinkAdapter
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

        self.notional.upgradeTo("0x2C67B0C0493e358cF368073bc0B5fA6F01E981e0", {"from": self.notional.owner()})
        self.notional.updateAssetRate(1, "0x8E3D447eBE244db6D28E2303bCa86Ef3033CFAd6", {"from": self.notional.owner()})
        self.notional.updateAssetRate(2, "0x719993E82974f5b5eA0c5ebA25c260CD5AF78E00", {"from": self.notional.owner()})
        self.notional.updateAssetRate(3, "0x612741825ACedC6F88D8709319fe65bCB015C693", {"from": self.notional.owner()})
        self.notional.updateAssetRate(4, "0x39D9590721331B13C8e9A42941a2B961B513E69d", {"from": self.notional.owner()})
        self.upgradeNotional()

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

        self.deployTradingModule()

    def upgradeNotional(self):
        tradingAction = deployArtifact(
            "scripts/artifacts/TradingAction.json",
            [],
            self.deployer,
            "VaultAccountAction",
            {"SettleAssetsExternal": "0x01713633a1b85a4a3d2f9430C68Bd4392c4a90eA"}
        )
        vaultAccountAction = deployArtifact(
            "scripts/artifacts/VaultAccountAction.json",
            [],
            self.deployer,
            "VaultAccountAction",
            {"TradingAction": tradingAction.address}
        )
        vaultAction = deployArtifact(
            "scripts/artifacts/VaultAction.json",
            [],
            self.deployer,
            "VaultAction",
            {"TradingAction": tradingAction.address}
        )
        newRouter = deployArtifact(
            "scripts/artifacts/Router.json",
            [[
                "0x38A4DfC0ff6588fD0c2142d14D4963A97356A245",
                "0xBf91ec7A64FCF0844e54d3198E50AD8fb4D68E93",
                "0xe3E38607A1E2d6881A32F1D78C5C232f14bdef22",
                "0xeA82Cfc621D5FA00E30c10531380846BB5aAfE79",
                "0x1d1a531CBcb969040Da7527bf1092DfC4FF7DD46",
                "0x8A096f6C6D89dBd3c3Df3EEBA45710Aa367F9A8c",
                "0xBf12d7e41a25f449293AB8cd1364Fe74A175bFa5",
                "0xa3707CD595F6AB810a84d04C92D8adE5f7593Db5",
                "0xfB56271c976A8b446B6D33D1Ec76C84F6AA53F1B",
                "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
                "0x5fd75e91Cc34DF9831Aa75903027FC34FeB9b931",
                "0xbE4AbA25915BAd390edf83B7e1ca44b6145F261e",
                vaultAccountAction.address,
                vaultAction.address
            ]],
            self.deployer,
            "Router"
        )
        self.notional.upgradeTo(newRouter.address, {'from': self.notional.owner()})

    def deployTradingModule(self, useFresh=False):
        if useFresh == False:
            self.tradingModule = Contract.from_abi("TradingModule", self.addresses["trading"]["proxy"], TradingModule.abi)
            impl = TradingModule.deploy(self.notional.address, self.tradingModule.address, {"from": self.deployer})
            self.tradingModule.upgradeTo(impl.address, {"from": self.notional.owner()})
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

