import eth_abi
from brownie import (
    network, 
    nProxy,
    nMockProxy,
    MetaStable2TokenAuraVault,
    Boosted3TokenAuraVault,
    Boosted3TokenAuraHelper,
    MetaStable2TokenAuraHelper,
    FlashLiquidator,
    nMockProxy
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
from brownie.network.state import Chain
from brownie.convert import to_bytes
from scripts.common import deployArtifact, get_vault_config, set_flags
from scripts.EnvironmentConfig import Environment
from eth_utils import keccak

chain = Chain()
ETH_ADDRESS = "0x0000000000000000000000000000000000000000"

StrategyConfig = {
    "balancer2TokenStrats": {
        "StratStableETHstETH": {
            "vaultConfig": get_vault_config(
                flags=set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True),
                currencyId=1,
                minAccountBorrowSize=1,
                maxBorrowMarketIndex=2,
                secondaryBorrowCurrencies=[0,0]
            ),
            "secondaryBorrowCurrency": None,
            "maxPrimaryBorrowCapacity": 100_000_000e8,
            "name": "Balancer Stable ETH-stETH Strategy",
            "primaryCurrency": 1, # ETH
            "poolId": "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080",
            "liquidityGauge": "0xcd4722b7c24c29e0413bdcd9e51404b4539d14ae",
            "auraRewardPool": "0xe4683fe8f53da14ca5dac4251eadfb3aa614d528",
            "maxUnderlyingSurplus": 2000e18, # 2000 ETH
            "maxPoolShare": Wei(1.5e3), # 15%
            "settlementSlippageLimitPercent": Wei(3e6), # 3%
            "postMaturitySettlementSlippageLimitPercent": Wei(5e6), # 5%
            "emergencySettlementSlippageLimitPercent": Wei(4e6), # 4%
            "settlementCoolDownInMinutes": 20, # 20 minute settlement cooldown
            "settlementWindow": 172800,  # 1-week settlement
            "oraclePriceDeviationLimitPercent": 200, # +/- 2%
            "poolSlippageLimitPercent": 9975, # 0.25%
        },
        "StratBoostedPoolDAIPrimary": {
            "vaultConfig": get_vault_config(
                flags=set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True),
                currencyId=2,
                minAccountBorrowSize=1,
                maxBorrowMarketIndex=3,
                secondaryBorrowCurrencies=[0,0]
            ),
            "secondaryBorrowCurrency": None,
            "maxPrimaryBorrowCapacity": 100_000_000e8,
            "name": "Balancer Boosted Pool Strategy",
            "primaryCurrency": 2, # DAI
            "poolId": "0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d",
            "liquidityGauge": "0xa6325e799d266632d347e41265a69af111b05403",
            "auraRewardPool": "0xfb6b1c1a1ea5618b3cfc20f81a11a97e930fa46b",
            "maxUnderlyingSurplus": 50000e18, # 50000 DAI
            "maxPoolShare": 2e3, # 20%
            "settlementSlippageLimitPercent": 3e6, # 5%
            "postMaturitySettlementSlippageLimitPercent": 5e6, # 5%
            "emergencySettlementSlippageLimitPercent": 4e6, # 4%
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "oraclePriceDeviationLimitPercent": 50, # +/- 0.5%
            "poolSlippageLimitPercent": 9900, # 1%
        },
        "StratBoostedPoolUSDCPrimary": {
            "vaultConfig": get_vault_config(
                flags=set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True),
                currencyId=3,
                minAccountBorrowSize=1,
                maxBorrowMarketIndex=3,
                secondaryBorrowCurrencies=[0,0]
            ),
            "secondaryBorrowCurrency": None,
            "maxPrimaryBorrowCapacity": 100_000_000e8,
            "name": "Balancer Boosted Pool Strategy",
            "primaryCurrency": 3, # USDC
            "poolId": "0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d",
            "liquidityGauge": "0xa6325e799d266632d347e41265a69af111b05403",
            "auraRewardPool": "0xfb6b1c1a1ea5618b3cfc20f81a11a97e930fa46b",
            "maxUnderlyingSurplus": 50000e6, # 50000 USDC
            "oracleWindowInSeconds": 0,
            "maxPoolShare": 2e3, # 20%
            "settlementSlippageLimitPercent": 3e6, # 5%
            "postMaturitySettlementSlippageLimitPercent": 5e6, # 5%
            "emergencySettlementSlippageLimitPercent": 4e6, # 4%
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "oraclePriceDeviationLimitPercent": 50, # +/- 0.5%
            "poolSlippageLimitPercent": 9900, # 1%
        }
    }
}

class BalancerEnvironment(Environment):
    def __init__(self, network) -> None:
        Environment.__init__(self, network)
        self.liquidator = self.deployLiquidator()

    def getStratConfig(self, strat):
        return StrategyConfig["balancer2TokenStrats"][strat]

    def initializeBalancerVault(self, vault, strat):
        stratConfig = StrategyConfig["balancer2TokenStrats"][strat]
        vault.initialize(
            [
                stratConfig["name"],
                stratConfig["primaryCurrency"],
                [
                    stratConfig["maxUnderlyingSurplus"],
                    stratConfig["settlementSlippageLimitPercent"], 
                    stratConfig["postMaturitySettlementSlippageLimitPercent"], 
                    stratConfig["emergencySettlementSlippageLimitPercent"], 
                    stratConfig["maxRewardTradeSlippageLimitPercent"],
                    stratConfig["maxPoolShare"],
                    stratConfig["settlementCoolDownInMinutes"],
                    stratConfig["oraclePriceDeviationLimitPercent"],
                    stratConfig["poolSlippageLimitPercent"]
                ]
            ],
            {"from": self.notional.owner()}
        )        

        self.notional.updateVault(
            vault.address,
            stratConfig["vaultConfig"],
            stratConfig["maxPrimaryBorrowCapacity"],
            {"from": self.notional.owner()}
        )

    def deployBalancerVault(self, strat, vaultContract, libs=None):
        stratConfig = StrategyConfig["balancer2TokenStrats"][strat]

        # Deploy external libs
        if libs != None:
            for lib in libs:
                lib.deploy({"from": self.deployer})

        return vaultContract.deploy(
            self.addresses["notional"],
            [
                stratConfig["auraRewardPool"],
                [
                    stratConfig["primaryCurrency"],
                    stratConfig["poolId"],
                    stratConfig["liquidityGauge"],
                    self.tradingModule.address,
                    stratConfig["settlementWindow"]
                ]
            ],
            {"from": self.deployer}
        )

    def deployVaultProxy(self, strat, impl, vaultContract, mockImpl=None):
        stratConfig = StrategyConfig["balancer2TokenStrats"][strat]

        if mockImpl == None:
            proxy = nProxy.deploy(impl.address, bytes(), {"from": self.deployer})
        else:
            proxy = nMockProxy.deploy(impl.address, bytes(), mockImpl, {"from": self.deployer})
        vaultProxy = Contract.from_abi(stratConfig["name"], proxy.address, vaultContract.abi)
        vaultProxy.initialize(
            [
                stratConfig["name"],
                stratConfig["primaryCurrency"],
                [
                    stratConfig["maxUnderlyingSurplus"],
                    stratConfig["settlementSlippageLimitPercent"], 
                    stratConfig["postMaturitySettlementSlippageLimitPercent"], 
                    stratConfig["emergencySettlementSlippageLimitPercent"], 
                    stratConfig["maxPoolShare"],
                    stratConfig["settlementCoolDownInMinutes"],
                    stratConfig["oraclePriceDeviationLimitPercent"],
                    stratConfig["poolSlippageLimitPercent"]
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

        return vaultProxy

    def deployLiquidator(self):
        liquidator = FlashLiquidator.deploy(
            self.notional, 
            "0x27182842E098f60e3D576794A5bFFb0777E025d3",
            "0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3",
            {"from": self.deployer}
        )
        liquidator.enableCurrencies([1, 2, 3], {"from": self.deployer})
        return liquidator

def getEnvironment(network = "mainnet"):
    if network == "mainnet-fork" or network == "hardhat-fork":
        network = "mainnet"
    return BalancerEnvironment(network)

def main():
    networkName = network.show_active()
    if networkName == "hardhat-fork":
        networkName = "mainnet"
    env = BalancerEnvironment(networkName)
    maturity = env.notional.getActiveMarkets(1)[0][1]

    vault1Impl = env.deployBalancerVault(
        "StratStableETHstETH", 
        MetaStable2TokenAuraVault,
        [MetaStable2TokenAuraHelper]
    )
    vault1 = env.deployVaultProxy("StratStableETHstETH", vault1Impl, MetaStable2TokenAuraVault)
    vault2Impl = env.deployBalancerVault(
        "StratBoostedPoolDAIPrimary", 
        Boosted3TokenAuraVault,
        [Boosted3TokenAuraHelper]
    )
    vault2 = env.deployVaultProxy("StratBoostedPoolDAIPrimary", vault2Impl, Boosted3TokenAuraVault)
    vault3Impl = env.deployBalancerVault(
        "StratBoostedPoolUSDCPrimary", 
        Boosted3TokenAuraVault,
        [Boosted3TokenAuraHelper]
    )
    vault3 = env.deployVaultProxy("StratBoostedPoolUSDCPrimary", vault3Impl, Boosted3TokenAuraVault)
