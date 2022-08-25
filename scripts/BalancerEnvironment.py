import eth_abi
from brownie import (
    network, 
    nProxy,
    MetaStable2TokenAuraVault,
    Boosted3TokenAuraVault,
    Boosted3TokenAuraHelper,
    MetaStable2TokenAuraHelper,
    MockStable2TokenAuraVault,
    MockBoosted3TokenAuraVault
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
        "StratStableETHstETH": {
            "vaultConfig": get_vault_config(
                flags=set_flags(0, ENABLED=True, ALLOW_ROLL_POSITION=True),
                currencyId=1,
                minAccountBorrowSize=1,
                maxBorrowMarketIndex=3,
                secondaryBorrowCurrencies=[0,0]
            ),
            "secondaryBorrowCurrency": None,
            "maxPrimaryBorrowCapacity": 100_000_000e8,
            "name": "Balancer Stable ETH-stETH Strategy",
            "primaryCurrency": 1, # ETH
            "poolId": "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080",
            "liquidityGauge": "0xcd4722b7c24c29e0413bdcd9e51404b4539d14ae",
            "auraRewardPool": "0xdcee1c640cc270121faf145f231fd8ff1d8d5cd4",
            "feeReceiver": "0x0190702d5e52e0269c9319144d3ad62a60ebe526",
            "maxUnderlyingSurplus": 100e18, # 10 ETH
            "oracleWindowInSeconds": 3600,
            "maxBalancerPoolShare": 2e3, # 20%
            "settlementSlippageLimit": 5e6, # 5%
            "postMaturitySettlementSlippageLimit": 10e6, # 10%
            "balancerOracleWeight": 0.6e4, # 60%
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "postMaturitySettlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "feePercentage": 1e2, # 1%
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "maxRewardTradeSlippageLimitPercent": 5e6
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
            "poolId": "0x7b50775383d3d6f0215a8f290f2c9e2eebbeceb20000000000000000000000fe",
            "liquidityGauge": "0x68d019f64a7aa97e2d4e7363aee42251d08124fb",
            "auraRewardPool": "0xcc2f52b57247f2bc58fec182b9a60dac5963d010",
            "feeReceiver": "0x0190702d5e52e0269c9319144d3ad62a60ebe526",
            "maxUnderlyingSurplus": 10000e18, # 10000 DAI
            "oracleWindowInSeconds": 0,
            "maxBalancerPoolShare": 2e3, # 20%
            "settlementSlippageLimit": 5e6, # 5%
            "postMaturitySettlementSlippageLimit": 10e6, # 10%
            "balancerOracleWeight": 0,
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "postMaturitySettlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "feePercentage": 1e2, # 1%
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "maxRewardTradeSlippageLimitPercent": 5e6
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
            "poolId": "0x7b50775383d3d6f0215a8f290f2c9e2eebbeceb20000000000000000000000fe",
            "liquidityGauge": "0x68d019f64a7aa97e2d4e7363aee42251d08124fb",
            "auraRewardPool": "0xcc2f52b57247f2bc58fec182b9a60dac5963d010",
            "feeReceiver": "0x0190702d5e52e0269c9319144d3ad62a60ebe526",
            "maxUnderlyingSurplus": 10000e6, # 10000 USDC
            "oracleWindowInSeconds": 0,
            "maxBalancerPoolShare": 2e3, # 20%
            "settlementSlippageLimit": 5e6, # 5%
            "postMaturitySettlementSlippageLimit": 10e6, # 10%
            "balancerOracleWeight": 0,
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "postMaturitySettlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "feePercentage": 1e2, # 1%
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "maxRewardTradeSlippageLimitPercent": 5e6
        }
    }
}

class BalancerEnvironment(Environment):
    def __init__(self, network) -> None:
        Environment.__init__(self, network)

    def deployBalancerVault(self, strat, vaultContract, libs=None):
        stratConfig = StrategyConfig["balancer2TokenStrats"][strat]

        # Deploy external libs
        if libs != None:
            for lib in libs:
                lib.deploy({"from": self.deployer})


        impl = vaultContract.deploy(
            self.addresses["notional"],
            [
                stratConfig["auraRewardPool"],
                [
                    stratConfig["primaryCurrency"],
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
                    stratConfig["settlementSlippageLimit"], 
                    stratConfig["postMaturitySettlementSlippageLimit"], 
                    stratConfig["maxBalancerPoolShare"],
                    stratConfig["balancerOracleWeight"],
                    stratConfig["settlementCoolDownInMinutes"],
                    stratConfig["postMaturitySettlementCoolDownInMinutes"],
                    stratConfig["feePercentage"],
                    stratConfig["maxRewardTradeSlippageLimitPercent"]
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

        return vaultProxy

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

    stableVault = env.deployBalancerVault(
        "StratStableETHstETH", 
        MetaStable2TokenAuraVault,
        [MetaStable2TokenAuraHelper]
    )
    env.mockStable2TokenAuraVault = MockStable2TokenAuraVault.deploy(
        stableVault.getStrategyContext(),
        {"from": env.deployer}
    )

    boosted3TokenVault = env.deployBalancerVault(
        "StratBoostedPoolDAIPrimary", 
        Boosted3TokenAuraVault,
        [Boosted3TokenAuraHelper]
    )

    env.mockThreeTokenAuraVault = MockBoosted3TokenAuraVault.deploy(
        boosted3TokenVault.getStrategyContext(),
        {"from": env.deployer}
    )

    return

    stableStrategyContext = stableVault.getStrategyContext()
    weightedStrategyContext = weightedVault.getStrategyContext()
    

    chain.undo()
    chain.undo()
    chain.sleep(maturity + 3600 * 24 - chain.time())
    chain.mine()

    weightedVault.settleVaultPostMaturity(
        maturity,
        vaultAccount["vaultShares"],
        eth_abi.encode_abi(
            ['(uint32,uint256,uint256,bytes)'],
            [[
                0,
                Wei(spotBalances["primaryBalance"] * 0.98),
                Wei(spotBalances["secondaryBalance"] * 0.98),
                eth_abi.encode_abi(
                    ['(uint16,uint8,uint32,bytes)'],
                    [[
                        1,
                        0,
                        Wei(5e6),
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

