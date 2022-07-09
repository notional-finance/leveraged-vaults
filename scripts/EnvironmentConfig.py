import json
import eth_abi
from brownie import (
    ZERO_ADDRESS,
    accounts, 
    network, 
    interface,
    TradingModule,
    nProxy,
    BalancerBoostController,
    Balancer2TokenVault,
    EmptyProxy,
    SettlementHelper,
    RewardHelper
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
from brownie.convert import to_bytes
from scripts.common import deployArtifact, get_vault_config, set_flags
from eth_utils import keccak

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

ETH_ADDRESS = "0x0000000000000000000000000000000000000000"

networks = {}

with open("v2.mainnet.json", "r") as f:
    networks["mainnet"] = json.load(f)

with open("v2.goerli.json", "r") as f:
    networks["goerli"] = json.load(f)

StrategyConfig = {
    "balancer2TokenStrats": {
        "Strat50ETH50USDC": {
            "vaultConfig": get_vault_config(
                flags=set_flags(0, ENABLED=True),
                minAccountBorrowSize=1,
                maxBorrowMarketIndex=3,
                secondaryBorrowCurrencies=[3,2] # USDC
            ),
            "secondaryBorrowCurrency": {
                "currencyId": 3, # USDC
                "maxCapacity": 100_000_000e8
            },
            "maxPrimaryBorrowCapacity": 100_000_000e8,
            "name": "Balancer 50ETH-50USDC Strategy",
            "primaryCurrency": 1, # ETH
            "poolId": "0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
            "liquidityGauge": "0x9ab7b0c7b154f626451c9e8a68dc04f58fb6e5ce",
            "maxUnderlyingSurplus": 10e18, # 10 ETH
            "oracleWindowInSeconds": 3600,
            "maxBalancerPoolShare": 1e3, # 10%
            "settlementSlippageLimit": 5e3, # 5%
            "postMaturitySettlementSlippageLimit": 10e3, # 10%
            "balancerOracleWeight": 0.6e4, # 60%
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "postMaturitySettlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
        }
    }
}

class Environment:
    def __init__(self, network) -> None:
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
        self.deployVeBalDelegator()
        self.deployBoostController()

        self.balancer2TokenStrats = {}
        self.deployBalancer2TokenVault("Strat50ETH50USDC")

    def upgradeNotional(self):
        tradingAction = deployArtifact(
            "scripts/artifacts/TradingAction.json", 
            [], 
            self.deployer, 
            "TradingAction", 
            {"SettleAssetsExternal": self.addresses["libs"]["SettleAssetsExternal"]}
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
            {"TradingAction": tradingAction.address})
        router = deployArtifact("scripts/artifacts/Router.json", [
            (
                self.addresses["actions"]["GovernanceAction"],
                self.addresses["actions"]["Views"],
                self.addresses["actions"]["InitializeMarketsAction"],
                self.addresses["actions"]["nTokenAction"],
                self.addresses["actions"]["BatchAction"],
                self.addresses["actions"]["AccountAction"],
                self.addresses["actions"]["ERC1155Action"],
                self.addresses["actions"]["LiquidateCurrencyAction"],
                self.addresses["actions"]["LiquidatefCashAction"],
                self.addresses["tokens"]["cETH"],
                self.addresses["actions"]["TreasuryAction"],
                self.addresses["actions"]["CalculationViews"],
                vaultAccountAction.address,
                vaultAction.address,
            )
        ], self.deployer, "Router")
        self.notional.upgradeTo(router.address, {'from': self.notional.owner()})

    def deployTradingModule(self):
        emptyImpl = EmptyProxy.deploy({"from": self.deployer})
        self.proxy = nProxy.deploy(emptyImpl.address, bytes(0), {"from": self.deployer})

        impl = TradingModule.deploy(self.notional.address, self.proxy.address, {"from": self.deployer})
        emptyProxy = Contract.from_abi("EmptyProxy", self.proxy.address, EmptyProxy.abi)
        emptyProxy.upgradeTo(impl.address, {"from": self.deployer})

        self.tradingModule = Contract.from_abi("TradingModule", self.proxy.address, TradingModule.abi)

        # ETH/USD oracle
        self.tradingModule.setPriceOracle(
            "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 
            "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419", 
            {"from": self.notional.owner()}
        )
        # DAI/USD oracle
        self.tradingModule.setPriceOracle(
            "0x6B175474E89094C44Da98b954EedeAC495271d0F",
            "0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9",
            {"from": self.notional.owner()}
        )
        # USDC/USD oracle
        self.tradingModule.setPriceOracle(
            "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            "0x8fffffd4afb6115b954bd326cbe7b4ba576818f6",
            {"from": self.notional.owner()}
        )
        # WBTC/USD oracle
        self.tradingModule.setPriceOracle(
            "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
            "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
            {"from": self.notional.owner()}
        )


    def deployVeBalDelegator(self):
        self.veBalDelegator = deployArtifact(
            "scripts/artifacts/VeBalDelegator.json",
            [
                self.addresses["balancer"]["BALETHPool"]["address"],
                self.addresses["balancer"]["veToken"],
                self.addresses["balancer"]["feeDistributor"],
                self.addresses["balancer"]["minter"],
                self.addresses["balancer"]["gaugeController"],
                self.addresses["staking"]["sNOTE"],
                self.addresses["balancer"]["delegateRegistry"],
                keccak(text="balancer.eth"),
                self.deployer.address
            ],
            self.deployer,
            "VeBalDelegator"
        )

    def deployBoostController(self):
        self.boostController = BalancerBoostController.deploy(
            self.addresses["notional"],
            self.veBalDelegator.address,
            {"from": self.deployer}
        )
        self.veBalDelegator.setManagerContract(
            self.boostController.address, 
            {"from": self.veBalDelegator.owner()}
        )

    def deployBalancer2TokenVault(self, strat):
        stratConfig = StrategyConfig["balancer2TokenStrats"][strat]
        # Deploy external libs
        SettlementHelper.deploy({"from": self.deployer})
        RewardHelper.deploy({"from": self.deployer})

        secondaryCurrencyId = stratConfig["secondaryBorrowCurrency"]["currencyId"]
        impl = Balancer2TokenVault.deploy(
            self.addresses["notional"],
            [
                secondaryCurrencyId,
                stratConfig["poolId"],
                self.boostController.address,
                stratConfig["liquidityGauge"],
                self.tradingModule.address,
                stratConfig["settlementWindow"],
            ],
            {"from": self.deployer}
        )

        proxy = nProxy.deploy(impl.address, bytes(0), {"from": self.deployer})
        vaultProxy = Contract.from_abi(stratConfig["name"], proxy.address, Balancer2TokenVault.abi)

        vaultProxy.initialize(
            [
                stratConfig["name"],
                stratConfig["primaryCurrency"],
                [
                    stratConfig["maxUnderlyingSurplus"],
                    stratConfig["oracleWindowInSeconds"],
                    stratConfig["maxBalancerPoolShare"],
                    stratConfig["settlementSlippageLimit"], 
                    stratConfig["postMaturitySettlementSlippageLimit"], 
                    stratConfig["balancerOracleWeight"],
                    stratConfig["settlementCoolDownInMinutes"],
                    stratConfig["postMaturitySettlementCoolDownInMinutes"], 
                ]
            ],
            {"from": self.notional.owner()}
        )

        self.balancer2TokenStrats[strat] = vaultProxy

        self.notional.updateVault(
            proxy.address,
            stratConfig["vaultConfig"],
            stratConfig["maxPrimaryBorrowCapacity"],
            {"from": self.notional.owner()}
        )

        if (stratConfig["secondaryBorrowCurrency"] != None):
            self.notional.updateSecondaryBorrowCapacity(
                proxy.address,
                stratConfig["secondaryBorrowCurrency"]["currencyId"],
                stratConfig["secondaryBorrowCurrency"]["maxCapacity"],
                {"from": self.notional.owner()}
            )

        self.boostController.setWhitelistForToken(
            stratConfig["liquidityGauge"], 
            vaultProxy.address,
            {"from": self.notional.owner() }
        )

def getEnvironment(network = "mainnet"):
    return Environment(network)

def main():
    networkName = network.show_active()
    if networkName == "hardhat-fork":
        networkName = "mainnet"
    env = Environment(networkName)
    vault = env.balancer2TokenStrats["Strat50ETH50USDC"]

    maturity = env.notional.getActiveMarkets(1)[0][1]

    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        10e18,
        maturity,
        5e8,
        0,
        eth_abi.encode_abi(
            ['(uint256,uint256,uint32,uint32)'],
            [[
                0,
                Wei(16970e8),
                0,
                0
            ]]
        ),
        {"from": env.whales["ETH"], "value": 10e18}
    )
