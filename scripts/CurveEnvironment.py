from brownie import (
    network, 
    Contract,
    Wei,
    Curve2TokenConvexVault,
    nProxy,
    nMockProxy
)
from scripts.common import get_vault_config, set_flags
from scripts.EnvironmentConfig import Environment

StrategyConfig = {
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
        "name": "Curve Stable ETH-stETH Strategy",
        "primaryCurrency": 1, # ETH
        "settlementWindow": 172800,  # 1-week settlement
        "rewardPool": "0x0A760466E1B4621579a82a39CB56Dda2F4E70f03",
        "pool": "0xdc24316b9ae028f1497c275eb9192a3ea0f67022",
        "maxUnderlyingSurplus": 2000e18, # 2000 ETH
        "maxPoolShare": Wei(1.5e3), # 15%
        "settlementSlippageLimitPercent": Wei(3e6), # 3%
        "postMaturitySettlementSlippageLimitPercent": Wei(5e6), # 5%
        "emergencySettlementSlippageLimitPercent": Wei(4e6), # 4%
        "maxRewardTradeSlippageLimitPercent": 2e6, # 2%
        "oraclePriceDeviationLimitPercent": 200, # +/- 2%
        "poolSlippageLimitPercent": 9975, # 0.25%
    }
}

class CurveEnvironment(Environment):
    def __init__(self, network) -> None:
        Environment.__init__(self, network)

    def deployVault(self, strat, vaultContract, libs=None):
        stratConfig = StrategyConfig[strat]

        # Deploy external libs
        if libs != None:
            for lib in libs:
                lib.deploy({"from": self.deployer})

        return vaultContract.deploy(
            self.addresses["notional"],
            [
                stratConfig["rewardPool"],
                [
                    stratConfig["primaryCurrency"],
                    stratConfig["pool"],
                    self.tradingModule.address
                ]
            ],
            {"from": self.deployer}
        )

    def deployVaultProxy(self, strat, impl, vaultContract, mockImpl=None):
        stratConfig = StrategyConfig[strat]

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

def getCurveEnvironment(network = "mainnet"):
    if network == "mainnet-fork" or network == "hardhat-fork":
        network = "mainnet"
    return CurveEnvironment(network)

def main():
    networkName = network.show_active()
    if networkName == "hardhat-fork":
        networkName = "mainnet"
    env = CurveEnvironment(networkName)

    impl = env.deployVault("StratStableETHstETH", Curve2TokenConvexVault)
    vault1 = env.deployVaultProxy("StratStableETHstETH", impl, Curve2TokenConvexVault)
    

