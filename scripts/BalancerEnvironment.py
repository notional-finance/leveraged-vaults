from brownie import (
    network, 
    accounts,
    nProxy,
    nMockProxy,
    EulerFlashLiquidator,
    AaveFlashLiquidator,
    nMockProxy
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
from brownie.network.state import Chain
from scripts.common import get_vault_config, set_flags
from scripts.EnvironmentConfig import Environment

chain = Chain()
ETH_ADDRESS = "0x0000000000000000000000000000000000000000"

StrategyConfig = {
    "mainnet": {
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
                "auraRewardPool": "0x59d66c58e83a26d6a0e35114323f65c3945c89c1",
                "maxUnderlyingSurplus": 2000e18, # 2000 ETH
                "maxPoolShare": Wei(1.5e3), # 15%
                "settlementSlippageLimitPercent": Wei(3e6), # 3%
                "postMaturitySettlementSlippageLimitPercent": Wei(5e6), # 5%
                "emergencySettlementSlippageLimitPercent": Wei(4e6), # 4%
                "settlementCoolDownInMinutes": 20, # 20 minute settlement cooldown
                "settlementWindow": 172800,  # 2 days
                "oraclePriceDeviationLimitPercent": 200, # +/- 2%
                "poolSlippageLimitPercent": 9975, # 0.25%
            },
            "StratAaveBoostedPoolDAIPrimary": {
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
            "StratAaveBoostedPoolUSDCPrimary": {
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
                "maxPoolShare": Wei(0.1e3), # 1%
                "settlementSlippageLimitPercent": 3e6, # 5%
                "postMaturitySettlementSlippageLimitPercent": 5e6, # 5%
                "emergencySettlementSlippageLimitPercent": 4e6, # 4%
                "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
                "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
                "oraclePriceDeviationLimitPercent": 50, # +/- 0.5%
                "poolSlippageLimitPercent": 9900, # 1%
            },
            "StratEulerBoostedPoolDAIPrimary": {
                "vaultConfig": get_vault_config(
                    flags=set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True),
                    currencyId=2,
                    minAccountBorrowSize=1,
                    maxBorrowMarketIndex=2,
                    secondaryBorrowCurrencies=[0,0]
                ),
                "secondaryBorrowCurrency": None,
                "maxPrimaryBorrowCapacity": 100_000_000e8,
                "name": "Balancer Boosted Pool Strategy",
                "primaryCurrency": 2, # DAI
                "poolId": "0x50cf90b954958480b8df7958a9e965752f62712400000000000000000000046f",
                "liquidityGauge": "0xf53f2fee2a34f7f8d1bfe1b774a95cc79c121b34",
                "auraRewardPool": "0x9542ecd46f3e661e4a53ee63c0ab764196df1f8a",
                "maxUnderlyingSurplus": 50000e18, # 50000 DAI
                "maxPoolShare": Wei(0.1e3), # 1%
                "settlementSlippageLimitPercent": Wei(0.5e6), # 0.5%
                "postMaturitySettlementSlippageLimitPercent": Wei(0.5e6), # 0.5%
                "emergencySettlementSlippageLimitPercent": Wei(0.5e6), # 0.5%
                "settlementCoolDownInMinutes": 20, # 6 hour settlement cooldown
                "settlementWindow": 172800,  # 2 days
                "oraclePriceDeviationLimitPercent": 100, # +/- 1%
                "poolSlippageLimitPercent": 9980, # 0.2%
            },
            "StratEulerBoostedPoolUSDCPrimary": {
                "vaultConfig": get_vault_config(
                    flags=set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True),
                    currencyId=3,
                    minAccountBorrowSize=1,
                    maxBorrowMarketIndex=2,
                    secondaryBorrowCurrencies=[0,0]
                ),
                "secondaryBorrowCurrency": None,
                "maxPrimaryBorrowCapacity": 100_000_000e8,
                "name": "Balancer Boosted Pool Strategy",
                "primaryCurrency": 3, # USDC
                "poolId": "0x50cf90b954958480b8df7958a9e965752f62712400000000000000000000046f",
                "liquidityGauge": "0xf53f2fee2a34f7f8d1bfe1b774a95cc79c121b34",
                "auraRewardPool": "0x9542ecd46f3e661e4a53ee63c0ab764196df1f8a",
                "maxUnderlyingSurplus": 50000e6, # 50000 USDC
                "oracleWindowInSeconds": 0,
                "maxPoolShare": 2e3, # 20%
                "settlementSlippageLimitPercent": Wei(0.5e6), # 0.5%
                "postMaturitySettlementSlippageLimitPercent": Wei(0.5e6), # 0.5%
                "emergencySettlementSlippageLimitPercent": Wei(0.5e6), # 0.5%
                "settlementCoolDownInMinutes": 20, # 6 hour settlement cooldown
                "settlementWindow": 172800,  # 2 days
                "oraclePriceDeviationLimitPercent": 100, # +/- 1%
                "poolSlippageLimitPercent": 9980, # 0.2%
            }
        }
    },
    "arbitrum": {
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
                "poolId": "0x9791d590788598535278552eecd4b211bfc790cb000000000000000000000498",
                "liquidityGauge": "0x260cbb867359a1084ec97de4157d06ca74e89415",
                "auraRewardPool": "0xa7bdad177d474f946f3cdeb4bcea9d24cf017471",
                "maxUnderlyingSurplus": 2000e18, # 2000 ETH
                "maxPoolShare": Wei(1.5e3), # 15%
                "settlementSlippageLimitPercent": Wei(3e6), # 3%
                "postMaturitySettlementSlippageLimitPercent": Wei(5e6), # 5%
                "emergencySettlementSlippageLimitPercent": Wei(4e6), # 4%
                "oraclePriceDeviationLimitPercent": 200, # +/- 2%
                "poolSlippageLimitPercent": 9975, # 0.25%
            },
            "StratStablestETHETH": {
                "vaultConfig": get_vault_config(
                    flags=set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True),
                    currencyId=5,
                    minAccountBorrowSize=1,
                    maxBorrowMarketIndex=2,
                    secondaryBorrowCurrencies=[0,0]
                ),
                "secondaryBorrowCurrency": None,
                "maxPrimaryBorrowCapacity": 100_000_000e8,
                "name": "Balancer Stable stETH-ETH Strategy",
                "primaryCurrency": 5, # stETH
                "poolId": "0x9791d590788598535278552eecd4b211bfc790cb000000000000000000000498",
                "liquidityGauge": "0x260cbb867359a1084ec97de4157d06ca74e89415",
                "auraRewardPool": "0xa7bdad177d474f946f3cdeb4bcea9d24cf017471",
                "maxUnderlyingSurplus": 2000e18, # 2000 ETH
                "maxPoolShare": Wei(1.5e3), # 15%
                "settlementSlippageLimitPercent": Wei(3e6), # 3%
                "postMaturitySettlementSlippageLimitPercent": Wei(5e6), # 5%
                "emergencySettlementSlippageLimitPercent": Wei(4e6), # 4%
                "oraclePriceDeviationLimitPercent": 200, # +/- 2%
                "poolSlippageLimitPercent": 9975, # 0.25%
            },
            "StratAaveBoostedPoolDAIPrimary": {
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
                "poolId": "0xc6eee8cb7643ec2f05f46d569e9ec8ef8b41b389000000000000000000000475",
                "liquidityGauge": "0xac3fc6075b90c4f793e3edab50e5568d2f9f18d7",
                "auraRewardPool": "0x237c47c7a0c4236049b872a6972cfc0729b0d362",
                "maxUnderlyingSurplus": 50000e18, # 50000 DAI
                "maxPoolShare": 2e3, # 20%
                "settlementSlippageLimitPercent": Wei(3e6), # 3%
                "postMaturitySettlementSlippageLimitPercent": Wei(5e6), # 5%
                "emergencySettlementSlippageLimitPercent": 4e6, # 4%
                "oraclePriceDeviationLimitPercent": 50, # +/- 0.5%
                "poolSlippageLimitPercent": 9900, # 1%
            },
        },
    }
}

class BalancerEnvironment(Environment):
    def __init__(self, network) -> None:
        Environment.__init__(self, network)
        self.eulerLiquidator = self.deployEulerLiquidator()

    def getStratConfig(self, strat):
        return StrategyConfig[self.network]["balancer2TokenStrats"][strat]

    def initializeBalancerVault(self, vault, strat):
        stratConfig = StrategyConfig[self.network]["balancer2TokenStrats"][strat]
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
        stratConfig = StrategyConfig[self.network]["balancer2TokenStrats"][strat]

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
                    self.tradingModule.address
                ]
            ],
            {"from": self.deployer}
        )

    def deployVaultProxy(self, strat, impl, vaultContract, mockImpl=None):
        stratConfig = StrategyConfig[self.network]["balancer2TokenStrats"][strat]

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
                    stratConfig["emergencySettlementSlippageLimitPercent"], 
                    stratConfig["maxPoolShare"],
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

    def deployEulerLiquidator(self):
        liquidator = EulerFlashLiquidator.deploy(
            self.notional, 
            "0x27182842E098f60e3D576794A5bFFb0777E025d3",
            "0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3",
            {"from": self.deployer}
        )
        liquidator.enableCurrencies([1, 2, 3, 4], {"from": self.deployer})
        return liquidator

    def deployAaveLiquidator(self):
        liquidator = AaveFlashLiquidator.deploy(
            self.notional,
            "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
            {"from": self.deployer}            
        )
        liquidator.enableCurrencies([1, 2, 3, 4], {"from": self.deployer})
        return liquidator

def getEnvironment(network = "mainnet"):
    if network == "mainnet-fork" or network == "hardhat-fork":
        network = "mainnet"
    if network == "arbitrum-fork" or network == "arbitrum-one":
        network = "arbitrum"
    return BalancerEnvironment(network)

def main():
    env = getEnvironment(network.show_active())
    maturity = env.notional.getActiveMarkets(1)[0][1]