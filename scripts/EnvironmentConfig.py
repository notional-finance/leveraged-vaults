import json
import eth_abi
from brownie import (
    ZERO_ADDRESS,
    accounts, 
    network, 
    interface,
    BalancerV2Adapter,
    TradingModule,
    nProxy,
    BalancerBoostController,
    Balancer2TokenVault,
    EmptyProxy,
    nUpgradeableBeacon,
    nBeaconProxy
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
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
                secondaryBorrowCurrencies=[3,0,0] # USDC
            ),
            "secondaryBorrowCurrency": {
                "currencyId": 3, # USDC
                "maxCapacity": 100_000_000e8
            },
            "maxPrimaryBorrowCapacity": 100_000_000e8,
            "name": "Strat50ETH50USDC",
            "primaryCurrency": 1, # ETH
            "poolId": "0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
            "liquidityGauge": "0x9ab7b0c7b154f626451c9e8a68dc04f58fb6e5ce",
            "oracleWindow": 3600,
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "settlementPercentage": 0.2e8, # 20% settlement percentage
            "settlementCoolDown": 3600 * 6 # 6 hour settlement cooldown
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
        self.deployBalancer2TokenVault(StrategyConfig["balancer2TokenStrats"]["Strat50ETH50USDC"])

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
        self.balancerV2Adapter = BalancerV2Adapter.deploy(self.balancerVault.address, {"from": self.deployer})
        impl = TradingModule.deploy(
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            self.balancerV2Adapter.address,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            ZERO_ADDRESS,            
            {"from": self.deployer}
        )

        initData = impl.initialize.encode_input(self.deployer.address)
        self.proxy = nProxy.deploy(impl.address, initData, {"from": self.deployer})
        self.tradingModule = Contract.from_abi("TradingModule", self.proxy.address, interface.ITradingModule.abi)

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
            self.veBalDelegator.address,
            self.addresses["notional"],
            {"from": self.deployer}
        )
        self.veBalDelegator.setManagerContract(
            self.boostController.address, 
            {"from": self.veBalDelegator.owner()}
        )

    def deployBalancer2TokenVault(self, stratConfig):

        # Deploy empty proxy in order to call updateVault
        stratVault = EmptyProxy.deploy({"from": self.deployer})
        beacon = nUpgradeableBeacon.deploy(stratVault, {"from": self.deployer})
        proxy = nBeaconProxy.deploy(beacon.address, bytes(), {"from": self.deployer})

        self.notional.updateVault(
            proxy.address,
            stratConfig["vaultConfig"],
            stratConfig["maxPrimaryBorrowCapacity"],
            {"from": self.notional.owner()}
        )

        secondaryCurrencyId = 0
        if (stratConfig["secondaryBorrowCurrency"] != None):
            self.notional.updateSecondaryBorrowCapacity(
                proxy.address,
                stratConfig["secondaryBorrowCurrency"]["currencyId"],
                stratConfig["secondaryBorrowCurrency"]["maxCapacity"],
                {"from": self.notional.owner()}
            )
            secondaryCurrencyId = stratConfig["secondaryBorrowCurrency"]["currencyId"]

        # Upgrade to actual implementation
        stratVault = Balancer2TokenVault.deploy(
            self.addresses["notional"],
            stratConfig["primaryCurrency"],
            True,
            True,
            [
                secondaryCurrencyId,
                self.addresses["tokens"]["WETH"],
                self.addresses["balancer"]["vault"],
                stratConfig["poolId"],
                self.boostController.address,
                stratConfig["liquidityGauge"],
                self.tradingModule.address,
                stratConfig["settlementWindow"],
            ],
            {"from": self.deployer}
        )
        beacon.upgradeTo(stratVault.address, {"from": self.deployer})
        vaultProxy = Contract.from_abi(
            stratConfig["name"], 
            proxy.address, 
            Balancer2TokenVault.abi
        )
        vaultProxy.initialize(
            stratConfig["oracleWindow"],
            stratConfig["settlementPercentage"], 
            stratConfig["settlementCoolDown"],
            {"from": self.notional.owner()}
        )
        self.balancer2TokenStrats[stratConfig["name"]] = vaultProxy

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
        True,
        5e8,
        0,
        eth_abi.encode_abi(
            ['(uint256,uint256,uint32)'],
            [[
                0,
                Wei(16768e8),
                0
            ]]
        ),
        {"from": env.whales["ETH"], "value": 10e18},
    )