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
    RewardHelper,
    MockBalancerUtils
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
from brownie.convert import to_bytes
from brownie.network.state import Chain
from scripts.common import deployArtifact, get_vault_config, set_flags
from eth_utils import keccak

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

        # Deploy mocks to access internal library functions
        self.mockBalancerUtils = MockBalancerUtils.deploy({"from": self.deployer});

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

        print(eth_abi.encode_abi(
            ["address","(uint16,bytes32,address,address,address,uint32)"],
            [self.addresses["notional"], [
                secondaryCurrencyId,
                to_bytes(stratConfig["poolId"], "bytes32"),
                "0x35bc5aaa9964699d5e5698a0e817d60bc11154f8",
                stratConfig["liquidityGauge"],
                "0xe56b95122909474ddd46c091e1d40af0fe52af79",
                stratConfig["settlementWindow"],
            ]]
        ).hex())

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

    vaultAccount = env.notional.getVaultAccount(env.whales["ETH"], vault.address)

    print(env.notional.exitVault.encode_input(
        env.whales["ETH"],
        "0xc45d28d78f0d60f48230ce044b0370b47078b21e",
        env.whales["ETH"],
        90257630518,
        5e8,
        0,
        eth_abi.encode_abi(
            ['(uint32,uint256,uint256,bytes)'],
            [[
                0,
                Wei(14916784772283813990 * 0.98),
                Wei(16888857974 * 0.98),
                eth_abi.encode_abi(
                    ['(uint16,uint8,uint16,bytes)'],
                    [[
                        1,
                        0,
                        500,
                        eth_abi.encode_abi(
                            ['(uint24)'],
                            [[3000]]
                        )
                    ]]
                )
            ]]
        )
    ))

    env.notional.exitVault(
        env.whales["ETH"],
        vault.address,
        env.whales["ETH"],
        vaultAccount["vaultShares"],
        5e8,
        0,
        eth_abi.encode_abi(
            ['(uint32,uint256,uint256,bytes)'],
            [[
                0,
                Wei(14916784772283813990 * 0.98),
                Wei(16888857974 * 0.98),
                eth_abi.encode_abi(
                    ['(uint16,uint8,uint16,bytes)'],
                    [[
                        1,
                        0,
                        500,
                        eth_abi.encode_abi(
                            ['(uint24)'],
                            [[3000]]
                        )
                    ]]
                )
            ]]
        ),
        {"from": env.whales["ETH"]}
    )

    chain.undo()

    settings = vault.getStrategyVaultSettings()
    vault.setStrategyVaultSettings(
        [settings[0], settings[1], 0, settings[3], settings[4], settings[5], settings[6], settings[7]], 
        {"from": env.notional.owner()}
    )

    vault.settleVaultEmergency(
        maturity,
        eth_abi.encode_abi(
            ['(uint32,uint256,uint256,bytes)'],
            [[
                0,
                Wei(14916784772283813990 * 0.98),
                Wei(16888857974 * 0.98),
                eth_abi.encode_abi(
                    ['(uint16,uint8,uint16,bytes)'],
                    [[
                        1,
                        0,
                        500,
                        eth_abi.encode_abi(
                            ['(uint24)'],
                            [[3000]]
                        )
                    ]]
                )
            ]]
        ),
        {"from": env.notional.owner()}
    )

    chain.undo()
    chain.sleep(maturity - 3600 * 24 * 6 - chain.time())
    chain.mine()

    print(vault.settleVaultNormal.encode_input(
        maturity,
        vaultAccount["vaultShares"] / 2,
        eth_abi.encode_abi(
            ['(uint32,uint256,uint256,bytes)'],
            [[
                0,
                Wei(14916784772283813990 / 2 * 0.98),
                Wei(16888857974 / 2 * 0.98),
                eth_abi.encode_abi(
                    ['(uint16,uint8,uint16,bytes)'],
                    [[
                        1,
                        0,
                        500,
                        eth_abi.encode_abi(
                            ['(uint24)'],
                            [[3000]]
                        )
                    ]]
                )
            ]]
        )
    ))

    print(vault.settleVaultPostMaturity.encode_input(
        maturity,
        Wei(90316937079),
        eth_abi.encode_abi(
            ['(uint32,uint256,uint256,bytes)'],
            [[
                0,
                Wei(14916784772283813990 * 0.98),
                Wei(16888857974 * 0.98),
                eth_abi.encode_abi(
                    ['(uint16,uint8,uint16,bytes)'],
                    [[
                        1,
                        0,
                        500,
                        eth_abi.encode_abi(
                            ['(uint24)'],
                            [[3000]]
                        )
                    ]]
                )
            ]]
        )
    ))

    packedEncoder = eth_abi.codec.ABIEncoder(eth_abi.registry.registry_packed)

    print(vault.reinvestReward.encode_input([eth_abi.encode_abi(
        ['(uint16,(uint8,address,address,uint256,uint256,uint256,bytes),uint16,(uint8,address,address,uint256,uint256,uint256,bytes))'],
        [[
            1,
            [
                0,
                env.tokens["BAL"].address,
                ETH_ADDRESS,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(uint24)'],
                    [[3000]]
                )                   
            ],
            1,
            [
                2,
                env.tokens["BAL"].address,
                env.tokens["USDC"].address,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(bytes)'],
                    [[
                        packedEncoder.encode_abi(
                            ["address", "uint24", "address", "uint24", "address"], 
                            [
                                env.tokens["BAL"].address, 
                                3000, 
                                env.tokens["WETH"].address,
                                3000, 
                                env.tokens["USDC"].address
                            ]
                        )                 
                    ]]
                )          
            ]
        ]]
    ), 0]))

    env.tokens["BAL"].transfer(vault.address, 2000e18, {"from": env.whales["BAL"]})

    vault.reinvestReward([eth_abi.encode_abi(
        ['(uint16,(uint8,address,address,uint256,uint256,uint256,bytes),uint16,(uint8,address,address,uint256,uint256,uint256,bytes))'],
        [[
            1,
            [
                0,
                env.tokens["BAL"].address,
                ETH_ADDRESS,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(uint24)'],
                    [[3000]]
                )                   
            ],
            1,
            [
                2,
                env.tokens["BAL"].address,
                env.tokens["USDC"].address,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(bytes)'],
                    [[
                        packedEncoder.encode_abi(
                            ["address", "uint24", "address", "uint24", "address"], 
                            [
                                env.tokens["BAL"].address, 
                                3000, 
                                env.tokens["WETH"].address,
                                3000, 
                                env.tokens["USDC"].address
                            ]
                        )                 
                    ]]
                )
            ]
        ]]
    ), 0], {"from": env.notional.owner()})

    vault.reinvestReward([eth_abi.encode_abi(
        ['(uint16,(uint8,address,address,uint256,uint256,uint256,bytes),uint16,(uint8,address,address,uint256,uint256,uint256,bytes))'],
        [[
            1,
            [
                0,
                env.tokens["BAL"].address,
                ETH_ADDRESS,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(uint24)'],
                    [[3000]]
                )                   
            ],
            1,
            [
                2,
                env.tokens["BAL"].address,
                env.tokens["USDC"].address,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(bytes)'],
                    [[
                        packedEncoder.encode_abi(
                            ["address", "uint24", "address", "uint24", "address"], 
                            [
                                env.tokens["BAL"].address, 
                                3000, 
                                env.tokens["WETH"].address,
                                3000, 
                                env.tokens["USDC"].address
                            ]
                        )                 
                    ]]
                )
            ]
        ]]
    ), 0], {"from": env.notional.owner()})
