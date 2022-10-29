import eth_abi
from brownie import (
    network, 
    nProxy,
    MetaStable2TokenAuraVault,
    Boosted3TokenAuraVault,
    Boosted3TokenAuraHelper,
    MetaStable2TokenAuraHelper,
    FlashLiquidator,
    ZERO_ADDRESS
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
from brownie.network.state import Chain
from brownie.convert import to_bytes
from brownie import accounts, interface
from scripts.common import deployArtifact, get_vault_config, set_flags, TRADE_TYPE,  set_dex_flags, set_trade_type_flags
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
            "settlementSlippageLimitPercent": 5e6, # 5%
            "postMaturitySettlementSlippageLimitPercent": 10e6, # 10%
            "emergencySettlementSlippageLimitPercent": 10e6, # 10%
            "maxRewardTradeSlippageLimitPercent": 5e6,
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "oraclePriceDeviationLimitPercent": 500, # +/- 5%
            "balancerPoolSlippageLimitPercent": 9900, # 1%
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
            "settlementSlippageLimitPercent": 5e6, # 5%
            "postMaturitySettlementSlippageLimitPercent": 10e6, # 10%
            "emergencySettlementSlippageLimitPercent": 10e6, # 10%
            "maxRewardTradeSlippageLimitPercent": 5e6,
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "oraclePriceDeviationLimitPercent": 50, # +/- 0.5%
            "balancerPoolSlippageLimitPercent": 9900, # 1%
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
            "settlementSlippageLimitPercent": 5e6, # 5%
            "postMaturitySettlementSlippageLimitPercent": 10e6, # 10%
            "emergencySettlementSlippageLimitPercent": 10e6, # 10%
            "maxRewardTradeSlippageLimitPercent": 5e6,
            "settlementCoolDownInMinutes": 60 * 6, # 6 hour settlement cooldown
            "settlementWindow": 3600 * 24 * 7,  # 1-week settlement
            "oraclePriceDeviationLimitPercent": 50, # +/- 0.5%
            "balancerPoolSlippageLimitPercent": 9900, # 1%
        }
    }
}

class BalancerEnvironment(Environment):
    def __init__(self, network) -> None:
        Environment.__init__(self, network)
        self.liquidator = self.deployLiquidator()
        self.WSTETHWhale = accounts.at('0x248ccbf4864221fc0e840f29bb042ad5bfc89b5c', force=True)

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
                    stratConfig["settlementWindow"]
                ]
            ],
            {"from": self.deployer}
        )

        proxy = nProxy.deploy(impl.address, bytes(0), {"from": self.deployer})
        vaultProxy = Contract.from_abi(stratConfig["name"], proxy.address, vaultContract.abi)

        print(
            vaultProxy.initialize.encode_input(
                [
                    stratConfig["name"],
                    stratConfig["primaryCurrency"],
                    [
                        stratConfig["maxUnderlyingSurplus"],
                        stratConfig["oracleWindowInSeconds"],
                        stratConfig["settlementSlippageLimitPercent"], 
                        stratConfig["postMaturitySettlementSlippageLimitPercent"], 
                        stratConfig["emergencySettlementSlippageLimitPercent"], 
                        stratConfig["maxRewardTradeSlippageLimitPercent"],
                        stratConfig["maxBalancerPoolShare"],
                        stratConfig["settlementCoolDownInMinutes"],
                        stratConfig["oraclePriceDeviationLimitPercent"],
                        stratConfig["balancerPoolSlippageLimitPercent"]
                    ]
                ]
            )
        )

        vaultProxy.initialize(
            [
                stratConfig["name"],
                stratConfig["primaryCurrency"],
                [
                    stratConfig["maxUnderlyingSurplus"],
                    stratConfig["oracleWindowInSeconds"],
                    stratConfig["settlementSlippageLimitPercent"], 
                    stratConfig["postMaturitySettlementSlippageLimitPercent"], 
                    stratConfig["emergencySettlementSlippageLimitPercent"], 
                    stratConfig["maxRewardTradeSlippageLimitPercent"],
                    stratConfig["maxBalancerPoolShare"],
                    stratConfig["settlementCoolDownInMinutes"],
                    stratConfig["oraclePriceDeviationLimitPercent"],
                    stratConfig["balancerPoolSlippageLimitPercent"]
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

    def balancer_trade_exact_in_single(self, sellToken, buyToken, amount, poolId):
        deadline = chain.time() + 20000
        return [
            TRADE_TYPE["EXACT_IN_SINGLE"], 
            sellToken, 
            buyToken, 
            amount, 
            0, 
            deadline, 
            eth_abi.encode_abi(
                ["(bytes32)"],
                [[to_bytes(poolId, "bytes32")]]
            )
        ]
    
    def test_current_spot_price(self, vault):
        spotPrice0 = vault.getSpotPrice(0)
        spotPrice1 = vault.getSpotPrice(1)
        assert 1/spotPrice1/spotPrice0 < 1e-35

    def test_spot_price_within_1_perc_of_pair_price_after_trading(self, vault):
        poolId = vault.getStrategyContext()["poolContext"]["basePool"].dict()['poolId']
        pool = vault.getStrategyContext()["poolContext"]["basePool"]["pool"]        
        self.tradingModule.setTokenPermissions(self.tradingModule.address, self.tokens["wstETH"].address, [True, set_dex_flags(0, BALANCER_V2=True, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], {"from": self.notional.owner()})
        self.tradingModule.setTokenPermissions(self.tradingModule.address, self.tokens["WETH"].address, [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], {"from": self.notional.owner()})
    
        # Trade
        self.tokens["wstETH"].transfer(self.tradingModule, 30000e18, {"from": self.WSTETHWhale})
        tradeCallData = self.balancer_trade_exact_in_single(self.tokens["wstETH"].address, self.tokens["WETH"].address, 30000e18, poolId)
        self.tradingModule.executeTradeWithDynamicSlippage(4, tradeCallData, 5e6, {"from": self.WSTETHWhale})

        # Trade in small increments to update the balancer oracle pair price 
        for i in range(0,10):
            self.tokens["wstETH"].transfer(self.tradingModule, 1e18, {"from": self.WSTETHWhale})
            tradeCallData = self.balancer_trade_exact_in_single(self.tokens["wstETH"].address, self.tokens["WETH"].address, 1e18, poolId)
            self.tradingModule.executeTradeWithDynamicSlippage(4, tradeCallData, 5e6, {"from": self.WSTETHWhale})
            tradeCallData = self.balancer_trade_exact_in_single(self.tokens["WETH"].address, self.tokens["wstETH"].address, 1e18, poolId)
            self.tradingModule.executeTradeWithDynamicSlippage(4, tradeCallData, 5e6, {"from": self.WSTETHWhale})
            chain.sleep(60)

        secondaryScaleFactor = vault.getStrategyContext()["poolContext"]["secondaryScaleFactor"]/1e18
        spotPrice0 = vault.getSpotPrice(0)/1e18
        pairPrice = interface.IPriceOracle(pool).getLatest(0)/1e18
        balancerPrice = 1/(pairPrice * secondaryScaleFactor)
        assert spotPrice0/balancerPrice-1 < 0.01

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

    vault1 = env.deployBalancerVault(
        "StratStableETHstETH", 
        MetaStable2TokenAuraVault,
        [MetaStable2TokenAuraHelper]
    )
    vault2 = env.deployBalancerVault(
        "StratBoostedPoolDAIPrimary", 
        Boosted3TokenAuraVault,
        [Boosted3TokenAuraHelper]
    )
    vault3 = env.deployBalancerVault(
        "StratBoostedPoolUSDCPrimary", 
        Boosted3TokenAuraVault,
        [Boosted3TokenAuraHelper]
    )

    env.test_current_spot_price(vault1)
    env.test_spot_price_within_1_perc_of_pair_price_after_trading(vault1)
