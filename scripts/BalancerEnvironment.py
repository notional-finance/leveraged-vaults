import eth_abi
from brownie import (
    network, 
    nProxy,
    Weighted2TokenAuraVault,
    MetaStable2TokenAuraVault,
    SettlementHelper,
    AuraRewardHelperExternal,
    MetaStable2TokenAuraRewardHelper,
    MetaStable2TokenAuraSettlementHelper,
    MetaStable2TokenAuraVaultHelper,
    Weighted2TokenAuraRewardHelper,
    Weighted2TokenAuraVaultHelper,
    MockWeighted2TokenOracleMath,
    MockStable2TokenOracleMath,
    MockTwoTokenPoolUtils,
    MockTwoTokenAuraStrategyUtils
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
from brownie.network.state import Chain
from scripts.common import deployArtifact, get_vault_config, set_flags
from scripts.EnvironmentConfig import Environment
from eth_utils import keccak

chain = Chain()
ETH_ADDRESS = "0x0000000000000000000000000000000000000000"

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
            "auraRewardPool": "0x71c8ea7395999aa2007ca860ce66dafa8d5c44fb",
            "feeReceiver": "0x0190702d5e52e0269c9319144d3ad62a60ebe526",
            "maxUnderlyingSurplus": 10e18, # 10 ETH
            "oracleWindowInSeconds": 3600,
            "maxBalancerPoolShare": 1e3, # 10%
            "settlementSlippageLimit": 5e3, # 5%
            "postMaturitySettlementSlippageLimit": 10e3, # 10%
            "balancerOracleWeight": 0.6e4, # 60%
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "postMaturitySettlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "feePercentage": 1e2, # 1%
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
        },
        "Strat50ETH50stETH": {
            "vaultConfig": get_vault_config(
                flags=set_flags(0, ENABLED=True),
                minAccountBorrowSize=1,
                maxBorrowMarketIndex=3,
                secondaryBorrowCurrencies=[0,0] # USDC
            ),
            "secondaryBorrowCurrency": None,
            "maxPrimaryBorrowCapacity": 100_000_000e8,
            "name": "Balancer 50ETH-50stETH Strategy",
            "primaryCurrency": 1, # ETH
            "poolId": "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080",
            "liquidityGauge": "0xcd4722b7c24c29e0413bdcd9e51404b4539d14ae",
            "auraRewardPool": "0xdcee1c640cc270121faf145f231fd8ff1d8d5cd4",
            "feeReceiver": "0x0190702d5e52e0269c9319144d3ad62a60ebe526",
            "maxUnderlyingSurplus": 10e18, # 10 ETH
            "oracleWindowInSeconds": 3600,
            "maxBalancerPoolShare": 1e3, # 10%
            "settlementSlippageLimit": 5e3, # 5%
            "postMaturitySettlementSlippageLimit": 10e3, # 10%
            "balancerOracleWeight": 0.6e4, # 60%
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "postMaturitySettlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "feePercentage": 1e2, # 1%
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
        }
    }
}

class BalancerEnvironment(Environment):
    def __init__(self, network) -> None:
        Environment.__init__(self, network)

    def deployBalancerVault(self, strat, vaultContract):
        stratConfig = StrategyConfig["balancer2TokenStrats"][strat]
        # Deploy external libs
        AuraRewardHelperExternal.deploy({"from": self.deployer})
        MetaStable2TokenAuraRewardHelper.deploy({"from": self.deployer})
        MetaStable2TokenAuraSettlementHelper.deploy({"from": self.deployer})
        MetaStable2TokenAuraVaultHelper.deploy({"from": self.deployer})
        Weighted2TokenAuraRewardHelper.deploy({"from": self.deployer})
        Weighted2TokenAuraVaultHelper.deploy({"from": self.deployer})
        SettlementHelper.deploy({"from": self.deployer})

        secondaryCurrencyId = 0
        if stratConfig["secondaryBorrowCurrency"] != None:
            secondaryCurrencyId = stratConfig["secondaryBorrowCurrency"]["currencyId"]
        impl = vaultContract.deploy(
            self.addresses["notional"],
            [
                stratConfig["primaryCurrency"],
                secondaryCurrencyId,
                stratConfig["auraRewardPool"],
                [
                    stratConfig["poolId"],
                    stratConfig["liquidityGauge"],
                    self.tradingModule.address,
                    stratConfig["settlementWindow"],
                    stratConfig["feeReceiver"]
                ]
            ],
            {"from": self.deployer}
        )

        proxy = nProxy.deploy(impl.address, bytes(0), {"from": self.deployer})
        vaultProxy = Contract.from_abi(stratConfig["name"], proxy.address, vaultContract.abi)

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
                    stratConfig["feePercentage"]
                ]
            ],
            {"from": self.notional.owner()}
        )

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

        strategyContext = vaultProxy.getStrategyContext()

        # Deploy mocks to access internal library functions
        self.mockWeighted2TokenOracleMath = MockWeighted2TokenOracleMath.deploy({"from": self.deployer})
        self.mockStable2TokenOracleMath = MockStable2TokenOracleMath.deploy({"from": self.deployer})
        self.mockTwoTokenPoolUtils = MockTwoTokenPoolUtils.deploy({"from": self.deployer})
        self.mockTwoTokenAuraStrategyUtils = MockTwoTokenAuraStrategyUtils.deploy(
            strategyContext["poolContext"],
            strategyContext["stakingContext"],
            {"from": self.deployer}
        )

        return vaultProxy

def getEnvironment(strategyName, network = "mainnet"):
    if network == "mainnet-fork" or network == "hardhat-fork":
        network = "mainnet"
    return BalancerEnvironment(network, strategyName)

def main():
    networkName = network.show_active()
    if networkName == "hardhat-fork":
        networkName = "mainnet"
    env = BalancerEnvironment(networkName)
    weightedVault = env.deployBalancerVault("Strat50ETH50USDC", Weighted2TokenAuraVault)
    stableVault = env.deployBalancerVault("Strat50ETH50stETH", MetaStable2TokenAuraVault)

    maturity = env.notional.getActiveMarkets(1)[0][1]

    return

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
                Wei(env.mockBalancerUtils.getOptimalSecondaryBorrowAmount(vault.getOracleContext(), 15e18) * 1e2),
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
        [settings[0], settings[1], 0, settings[3], settings[4], settings[5], settings[6], settings[7], settings[8]], 
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
