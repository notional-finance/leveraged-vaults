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
    accounts,
    interface
)
from brownie.network.contract import Contract
from brownie.convert.datatypes import Wei
from brownie.network.state import Chain
from brownie.convert import to_bytes
from scripts.common import deployArtifact, get_vault_config, set_flags, TRADE_TYPE, set_dex_flags, set_trade_type_flags, get_deposit_params
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
            "auraRewardPool": "0xdcee1c640cc270121faf145f231fd8ff1d8d5cd4",
            "maxUnderlyingSurplus": 2000e18, # 2000 ETH
            "maxBalancerPoolShare": Wei(1.5e3), # 15%
            "settlementSlippageLimitPercent": Wei(3e6), # 3%
            "postMaturitySettlementSlippageLimitPercent": Wei(3e6), # 3%
            "emergencySettlementSlippageLimitPercent": Wei(4e6), # 4%
            "settlementCoolDownInMinutes": 20, # 20 minute settlement cooldown
            "settlementWindow": 172800,  # 1-week settlement
            "oraclePriceDeviationLimitPercent": 200, # +/- 2%
            "balancerPoolSlippageLimitPercent": 9975, # 0.25%
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
            "auraRewardPool": "0x1e9f147241da9009417811ad5858f22ed1f9f9fd",
            "maxUnderlyingSurplus": 10000e18, # 10000 DAI
            "maxBalancerPoolShare": 2e3, # 20%
            "settlementSlippageLimitPercent": 5e6, # 5%
            "postMaturitySettlementSlippageLimitPercent": 10e6, # 10%
            "emergencySettlementSlippageLimitPercent": 10e6, # 10%
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
            "poolId": "0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d",
            "liquidityGauge": "0xa6325e799d266632d347e41265a69af111b05403",
            "auraRewardPool": "0x1e9f147241da9009417811ad5858f22ed1f9f9fd",
            "maxUnderlyingSurplus": 10000e6, # 10000 USDC
            "maxBalancerPoolShare": 2e3, # 20%
            "settlementSlippageLimitPercent": 5e6, # 5%
            "postMaturitySettlementSlippageLimitPercent": 10e6, # 10%
            "emergencySettlementSlippageLimitPercent": 10e6, # 10%
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
                    stratConfig["maxBalancerPoolShare"],
                    stratConfig["settlementCoolDownInMinutes"],
                    stratConfig["oraclePriceDeviationLimitPercent"],
                    stratConfig["balancerPoolSlippageLimitPercent"]
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
            proxy = nProxy.deploy(impl.address, bytes(0), {"from": self.deployer})
        else:
            proxy = nMockProxy.deploy(impl.address, bytes(0), mockImpl, {"from": self.deployer})
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

    def enterMaturity(self, vault, currencyId, maturityIndex, depositAmount, primaryBorrowAmount, account, callStatic=False, depositParams=None):
        maturity = self.notional.getActiveMarkets(currencyId)[maturityIndex][1]
        value = 0
        if currencyId == 1:
            value = depositAmount
        if depositParams == None:
            depositParams = get_deposit_params()
        if callStatic:
            self.notional.enterVault.call(
                account,
                vault.address,
                Wei(depositAmount),
                Wei(maturity),
                Wei(primaryBorrowAmount),
                0,
                depositParams,
                {"from": account, "value": Wei(value)}
            )
        else:
            self.notional.enterVault(
                account,
                vault.address,
                Wei(depositAmount),
                Wei(maturity),
                Wei(primaryBorrowAmount),
                0,
                depositParams,
                {"from": account, "value": Wei(value)}
            )
        return maturity 

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
    
    def balancer_trade_exact_in_batch(self, sellToken, buyToken, amount, swaps, assets, limits):
        deadline = chain.time() + 20000
        return [
            TRADE_TYPE["EXACT_IN_BATCH"], 
            sellToken, 
            buyToken, 
            amount, 
            0, 
            deadline, 
            eth_abi.encode_abi(
                ['((bytes32,uint256,uint256,uint256,bytes)[],address[],int256[])'],
                [[swaps, assets, limits]]
            )
        ]    


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


    # Set token permissions for the trading module
    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        env.tokens["DAI"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})
    
    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        env.tokens["USDT"].address, 
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        '0xae37D54Ae477268B9997d4161B96b8200755935c', # bb-a-dai
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        '0xA13a9247ea42D743238089903570127DdA72fE44', # bb-a-usd
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        '0x028171bCA77440897B824Ca71D1c56caC55b68A3', # aDAI
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        '0xA13a9247ea42D743238089903570127DdA72fE44', # aUSDC
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        '0x02d60b84491589974263d922D9cC7a3152618Ef6', # Wrapped aDAI
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    # Set up whale accounts
    stablecoin_Whale = accounts.at('0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7', force=True) 
    dai_Whale = accounts.at('0xf977814e90da44bfa03b6295a0616a897441acec', force=True) 
    usdc_Whale = accounts.at('0x55FE002aefF02F77364de339a1292923A15844B8', force=True) 
    aDai_Whale = accounts.at('0x2e4cf76b269f34d83bea428f4c35aa5645191259', force=True) 
    aUsdc_Whale = accounts.at('0x3c9ea5c4fec2a77e23dd82539f4414266fe8f757', force=True) 
    
    # Composable stable pool ID
    composablePoolId = "0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d"
    composablePoolAddress = "0xa13a9247ea42d743238089903570127dda72fe44"

    # DAI linear pool ID
    daiLinearPoolId = "0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337"
    daiLinearPoolAddress = '0xae37D54Ae477268B9997d4161B96b8200755935c'

    # USDC linear pool ID
    usdcLinearPoolId = "0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d"
    usdcLinearPoolAddress = '0x82698aecc9e28e9bb27608bd52cf57f704bd1b83'

    # Lower and upper bounds of the zero-fee trading range for the main token balance.
    lowerTargetDaiLinearPool = interface.ILinearPool(daiLinearPoolAddress).getTargets()[0]/1e26
    upperTargetDaiLinearPool = interface.ILinearPool(daiLinearPoolAddress).getTargets()[1]/1e26

    # Lower and upper bounds of the zero-fee trading range for the main token balance.
    lowerTargetUSDCLinearPool = interface.ILinearPool(usdcLinearPoolAddress).getTargets()[0]/1e26
    upperTargetUSDCLinearPool = interface.ILinearPool(usdcLinearPoolAddress).getTargets()[1]/1e26

    # test that the exchange rate between one linear token BPT and underlying tokens is constant given that we do not exceed the lowerTarget and upperTarget 
    daiBalance = interface.IERC20(env.tokens["DAI"].address).balanceOf(dai_Whale)/1e18
    bb_a_daiBalance = interface.IERC20(daiLinearPoolAddress).balanceOf(dai_Whale)/1e18
    bb_a_usdBalance = interface.IERC20(composablePoolAddress).balanceOf(dai_Whale)/1e18

    aDaiAddress = '0x028171bCA77440897B824Ca71D1c56caC55b68A3'
    aUsdcAddress = '0xbcca60bb61934080951369a648fb03df4f96263c'
    wrappedADaiAddress = '0x02d60b84491589974263d922D9cC7a3152618Ef6'
    wrappedAUsdcAddress = '0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de'





    # Scenario 1
    # inititalDaiAmount = Wei(1000e18)
    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18
    # env.tokens["DAI"].transfer(env.tradingModule, inititalDaiAmount, {"from": dai_Whale})

    # trade = env.balancer_trade_exact_in_batch(
    #     env.tokens["DAI"].address, 
    #     "0xA13a9247ea42D743238089903570127DdA72fE44",
    #     #"0xae37D54Ae477268B9997d4161B96b8200755935c", # bb-a-DAI 
    #     inititalDaiAmount,
    #     [
    #         # DAI -> bb-a-DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             inititalDaiAmount,
    #             bytes()
    #         ],
    #         # bb-a-DAI -> bb-a-USD
    #         [
    #             to_bytes("0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d", "bytes32"),
    #             1,
    #             2,
    #             0, # Entire amount from previous swap
    #             bytes()
    #         ]
    #     ],
    #     [env.tokens["DAI"].address, "0xae37D54Ae477268B9997d4161B96b8200755935c", "0xA13a9247ea42D743238089903570127DdA72fE44"],
    #     [inititalDaiAmount, 0, 0]
    # )
    

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})

    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalanceEnd = daiLinearPool[1]/1e18
    # aDaiPoolBalanceEnd = daiLinearPool[3]/1e18
    # bptPoolBalanceEnd = daiLinearPool[4]/1e18

    # daiBalanceAfterEntering = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)/1e18
    # bb_a_daiBalanceAfterEntering = interface.IERC20('0xae37D54Ae477268B9997d4161B96b8200755935c').balanceOf(env.tradingModule.address)
    # bb_a_usdBalanceAfterEntering = interface.IERC20('0xA13a9247ea42D743238089903570127DdA72fE44').balanceOf(env.tradingModule.address)

    # # interface.IERC20("0xA13a9247ea42D743238089903570127DdA72fE44").transfer(dai_Whale, bb_a_usdBalanceAfterEntering, {"from": env.tradingModule}) 

    # amountSecondTrade = Wei(bb_a_usdBalanceAfterEntering)
    # trade = env.balancer_trade_exact_in_batch(
    #     "0xA13a9247ea42D743238089903570127DdA72fE44",
    #     env.tokens["DAI"].address, 
    #     #"0xae37D54Ae477268B9997d4161B96b8200755935c", # bb-a-DAI 
    #     amountSecondTrade,
    #     [
    #         # bb-a-USD -> bb-a-DAI
    #         [
    #             to_bytes("0xa13a9247ea42d743238089903570127dda72fe4400000000000000000000035d", "bytes32"),
    #             0,
    #             1,
    #             amountSecondTrade,
    #             bytes()
    #         ],

    #         # bb-a-DAI -> DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             1,
    #             2,
    #             0, # Entire amount from previous swap
    #             bytes()
    #         ]
    #     ],
    #     ["0xA13a9247ea42D743238089903570127DdA72fE44", "0xae37D54Ae477268B9997d4161B96b8200755935c", env.tokens["DAI"].address],
    #     [amountSecondTrade, 0, 0]
    # )
    
    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})
    # daiBalanceAfterExiting = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)/1e18
    # bb_a_daiBalanceAfterExiting = interface.IERC20('0xae37D54Ae477268B9997d4161B96b8200755935c').balanceOf(env.tradingModule.address)/1e18
    # bb_a_usdBalanceAfterExiting = interface.IERC20('0xA13a9247ea42D743238089903570127DdA72fE44').balanceOf(env.tradingModule.address)/1e18
    
    # print("Initial Balance:", inititalDaiAmount/1e18)
    # print("Ending Balance:", daiBalanceAfterExiting)



    # # Scenario 2
    # inititalDaiAmount = 1000e18
    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27
    # totalMainInitial = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlyingInitial = totalMainInitial/bptPoolBalance
    # underlyingPoolProportionInitial = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # # approve the Wrapped DAI contract
    # env.tokens["DAI"].approve(wrappedADaiAddress, 2 ** 256 - 1, {"from": dai_Whale.address})
    
    # # mint wrapped aDAI
    # interface.IStaticATokenLM(wrappedADaiAddress).deposit(dai_Whale, inititalDaiAmount, 0, True, {"from": dai_Whale})

    # aDAIBalance = interface.IERC20(wrappedADaiAddress).balanceOf(dai_Whale.address)

    # interface.IERC20(wrappedADaiAddress).transfer(env.tradingModule, aDAIBalance, {"from": dai_Whale}) 

    # amount = Wei(aDAIBalance)
    # trade = env.balancer_trade_exact_in_batch(
    #     wrappedADaiAddress,
    #     env.tokens["DAI"].address, 
    #     amount,
    #     [
    #         # Wrapped aDAI -> bb-a-DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ],
    #         # bb-a-DAI -> DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             1,
    #             2,
    #             0, # Entire amount from previous swap
    #             bytes()
    #         ]
    #     ],
    #     [wrappedADaiAddress, daiLinearPoolAddress, env.tokens["DAI"].address],
    #     [amount, 0, 0]
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})

    # daiBalanceAfterExiting = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)/1e18


    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # underlyingPoolProportion = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27

    # totalMain = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlying = totalMain/bptPoolBalance

    # print("Initial Balance:", inititalDaiAmount/1e18)
    # print("Ending Balance:", daiBalanceAfterExiting)
    # print("Initial BPT value:", bptValueInUnderlyingInitial)
    # print("Ending BPT value:", bptValueInUnderlying)




    # Scenario 3
    inititalDaiAmount = 1000e18
    daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    daiPoolBalance = daiLinearPool[1]/1e18
    aDaiPoolBalance = daiLinearPool[3]/1e18
    bptPoolBalance = daiLinearPool[4]/1e18

    aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27
    totalMainInitial = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    bptValueInUnderlyingInitial = totalMainInitial/bptPoolBalance
    underlyingPoolProportionInitial = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # approve the Wrapped DAI contract
    env.tokens["DAI"].approve(wrappedADaiAddress, 2 ** 256 - 1, {"from": dai_Whale.address})
    
    # mint wrapped aDAI
    interface.IStaticATokenLM(wrappedADaiAddress).deposit(dai_Whale, inititalDaiAmount, 0, True, {"from": dai_Whale})

    aDAIBalance = interface.IERC20(wrappedADaiAddress).balanceOf(dai_Whale.address)

    interface.IERC20(wrappedADaiAddress).transfer(env.tradingModule, aDAIBalance, {"from": dai_Whale}) 

    amount = Wei(aDAIBalance)
    trade = env.balancer_trade_exact_in_batch(
        wrappedADaiAddress,
        daiLinearPoolAddress, 
        amount,
        [
            # Wrapped aDAI -> bb-a-DAI
            [
                to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
                0,
                1,
                amount,
                bytes()
            ],
        ],
        [wrappedADaiAddress, daiLinearPoolAddress],
        [amount, 0]
    )

    env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})
    bb_a_dai_balance = interface.IERC20(daiLinearPoolAddress).balanceOf(env.tradingModule.address)

    amount = Wei(bb_a_dai_balance)
    trade = env.balancer_trade_exact_in_batch(
        daiLinearPoolAddress,
        wrappedADaiAddress, 
        amount,
        [
            # bb-a-DAI -> Wrapped aDAI
            [
                to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
                0,
                1,
                amount,
                bytes()
            ]
        ],
        [daiLinearPoolAddress, wrappedADaiAddress],
        [amount, 0]
    )

    env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})

    wrappedADaiBalanceAfterExiting = interface.IERC20(wrappedADaiAddress).balanceOf(env.tradingModule.address)/1e18


    daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    daiPoolBalance = daiLinearPool[1]/1e18
    aDaiPoolBalance = daiLinearPool[3]/1e18
    bptPoolBalance = daiLinearPool[4]/1e18

    underlyingPoolProportion = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27

    totalMain = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    bptValueInUnderlying = totalMain/bptPoolBalance

    print("Initial wrapped aDAI Balance:", aDAIBalance/1e18)
    print("Ending Balance:", wrappedADaiBalanceAfterExiting)
    print("Initial BPT value:", bptValueInUnderlyingInitial)
    print("Ending BPT value:", bptValueInUnderlying)



    # Scenario 4
    # inititalDaiAmount = 1000e18
    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27
    # totalMainInitial = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlyingInitial = totalMainInitial/bptPoolBalance
    # underlyingPoolProportionInitial = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # interface.IERC20(env.tokens["DAI"].address).transfer(env.tradingModule, inititalDaiAmount, {"from": dai_Whale}) 

    # amount = Wei(inititalDaiAmount)
    # trade = env.balancer_trade_exact_in_batch(
    #     env.tokens["DAI"].address,
    #     daiLinearPoolAddress, 
    #     amount,
    #     [
    #         # DAI -> bb-a-DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ],
    #     ],
    #     [env.tokens["DAI"].address, daiLinearPoolAddress],
    #     [amount, 0]
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})
    # bb_a_dai_balance = interface.IERC20(daiLinearPoolAddress).balanceOf(env.tradingModule.address)

    # amount = Wei(bb_a_dai_balance)
    # trade = env.balancer_trade_exact_in_batch(
    #     daiLinearPoolAddress,
    #     env.tokens["DAI"].address, 
    #     amount,
    #     [
    #         # bb-a-DAI -> DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ]
    #     ],
    #     [daiLinearPoolAddress, env.tokens["DAI"].address],
    #     [amount, 0]
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})

    # daiBalanceAfterExiting = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)/1e18


    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # underlyingPoolProportion = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27

    # totalMain = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlying = totalMain/bptPoolBalance

    # print("Initial wrapped aDAI Balance:", inititalDaiAmount/1e18)
    # print("Ending Balance:", daiBalanceAfterExiting)
    # print("Initial BPT value:", bptValueInUnderlyingInitial)
    # print("Ending BPT value:", bptValueInUnderlying)



    # # Scenario 5
    # inititalDaiAmount = 16000000e18
    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27
    # totalMainInitial = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlyingInitial = totalMainInitial/bptPoolBalance
    # underlyingPoolProportionInitial = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # # approve the Wrapped DAI contract
    # env.tokens["DAI"].approve(wrappedADaiAddress, 2 ** 256 - 1, {"from": dai_Whale.address})
    
    # # mint wrapped aDAI
    # interface.IStaticATokenLM(wrappedADaiAddress).deposit(dai_Whale, inititalDaiAmount, 0, True, {"from": dai_Whale})

    # aDAIBalance = interface.IERC20(wrappedADaiAddress).balanceOf(dai_Whale.address)

    # interface.IERC20(wrappedADaiAddress).transfer(env.tradingModule, aDAIBalance, {"from": dai_Whale}) 

    # amount = Wei(aDAIBalance)
    # trade = env.balancer_trade_exact_in_batch(
    #     wrappedADaiAddress,
    #     env.tokens["DAI"].address, 
    #     amount,
    #     [
    #         # Wrapped aDAI -> bb-a-DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ],

    #         # Wrapped bb-a-DAI -> DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             1,
    #             2,
    #             0,
    #             bytes()
    #         ],
    #     ],
    #     [wrappedADaiAddress, daiLinearPoolAddress, env.tokens["DAI"].address],
    #     [amount, 0, 0]
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})
    # dai_balance = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)


    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27
    # totalMainPostTrade = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlyingPostTrade = totalMainPostTrade/bptPoolBalance
    # underlyingPoolProportionPostTrade = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # interface.IERC20(env.tokens["DAI"].address).transfer(dai_Whale, dai_balance, {"from": env.tradingModule}) 

    # daiDeposit = 10000*1e18
    # interface.IERC20(env.tokens["DAI"].address).transfer(env.tradingModule, daiDeposit, {"from": dai_Whale}) 
    # amount = Wei(daiDeposit)
    # trade = env.balancer_trade_exact_in_batch(
    #     env.tokens["DAI"].address,
    #     daiLinearPoolAddress,
    #     amount,
    #     [
    #         # DAI -> bb-a-DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ]
    #     ],
    #     [env.tokens["DAI"].address, daiLinearPoolAddress],
    #     [amount, 0]
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})


    # bb_a_dai_balance = interface.IERC20(daiLinearPoolAddress).balanceOf(env.tradingModule.address)

    # amount = Wei(bb_a_dai_balance)
    # trade = env.balancer_trade_exact_in_batch(
    #     daiLinearPoolAddress,
    #     env.tokens["DAI"].address, 
    #     amount,
    #     [
    #         # bb-a-DAI -> DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ]
    #     ],
    #     [daiLinearPoolAddress, env.tokens["DAI"].address],
    #     [amount, 0]
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})

    # daiBalanceAfterExiting = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)/1e18

    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # underlyingPoolProportion = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27

    # totalMain = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlying = totalMain/bptPoolBalance

    # print("inititalDaiAmount:", inititalDaiAmount/1e18)
    # print("inititalDaiAmount:", dai_balance/1e18)
    # print("Initial wrapped aDAI Balance:", daiDeposit/1e18)
    # print("Ending Balance:", daiBalanceAfterExiting)
    # print("Initial BPT value:", bptValueInUnderlyingInitial)
    # print("Post trade BPT value:", bptValueInUnderlyingPostTrade)
    # print("Ending BPT value:", bptValueInUnderlying)


    # # Scenario 7
    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # inititalDaiAmount = daiLinearPool[1]*0.99999999999999999

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27
    # totalMainInitial = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlyingInitial = totalMainInitial/bptPoolBalance
    # underlyingPoolProportionInitial = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # # approve the Wrapped DAI contract
    # env.tokens["DAI"].approve(wrappedADaiAddress, 2 ** 256 - 1, {"from": dai_Whale.address})
    
    # # mint wrapped aDAI
    # interface.IStaticATokenLM(wrappedADaiAddress).deposit(dai_Whale, inititalDaiAmount, 0, True, {"from": dai_Whale})

    # aDAIBalance = interface.IERC20(wrappedADaiAddress).balanceOf(dai_Whale.address)

    # interface.IERC20(wrappedADaiAddress).transfer(env.tradingModule, aDAIBalance, {"from": dai_Whale}) 

    # amount = Wei(aDAIBalance)
    # trade = env.balancer_trade_exact_in_batch(
    #     wrappedADaiAddress,
    #     env.tokens["DAI"].address, 
    #     amount,
    #     [
    #         # Wrapped aDAI -> bb-a-DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ],

    #         # Wrapped bb-a-DAI -> DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             1,
    #             2,
    #             0,
    #             bytes()
    #         ],
    #     ],
    #     [wrappedADaiAddress, daiLinearPoolAddress, env.tokens["DAI"].address],
    #     [amount, 0, 0]
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})
    # dai_balance = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)


    # daiLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalance = daiLinearPool[1]/1e18
    # aDaiPoolBalance = daiLinearPool[3]/1e18
    # bptPoolBalance = daiLinearPool[4]/1e18

    # aDaiToDaiExchangeRate = interface.IStaticATokenLM(wrappedADaiAddress).rate()/1e27
    # totalMainPostTrade = aDaiPoolBalance * aDaiToDaiExchangeRate + daiPoolBalance
    # bptValueInUnderlyingPostTrade = totalMainPostTrade/bptPoolBalance
    # underlyingPoolProportionPostTrade = daiPoolBalance/(aDaiPoolBalance+daiPoolBalance)

    # interface.IERC20(env.tokens["DAI"].address).transfer(dai_Whale, dai_balance, {"from": env.tradingModule}) 













    # # approve the Wrapped DAI contract
    # env.tokens["DAI"].approve(wrappedADaiAddress, 2 ** 256 - 1, {"from": dai_Whale.address})
    # # mint wrapped aDAI
    # interface.IStaticATokenLM(wrappedADaiAddress).deposit(dai_Whale, 1000e18, 0, True, {"from": dai_Whale})

    # bptProportion = 1000/totalMain

    # aDAIBalance = interface.IERC20(wrappedADaiAddress).balanceOf(dai_Whale.address)

    # interface.IERC20(wrappedADaiAddress).transfer(env.tradingModule, aDAIBalance, {"from": dai_Whale}) 

    # # interface.IERC20("0x028171bCA77440897B824Ca71D1c56caC55b68A3").transfer(env.tradingModule, 1000e18, {"from": dai_Whale}) 

    # amount = Wei(aDAIBalance)
    # trade = env.balancer_trade_exact_in_batch(
    #     wrappedADaiAddress,
    #     daiLinearPoolAddress,
    #     # env.tokens["DAI"].address, 
    #     amount,
    #     [
    #         # Wrapped aDAI -> bb-a-DAI
    #         [
    #             to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #             0,
    #             1,
    #             amount,
    #             bytes()
    #         ],
    #         # # bb-a-DAI -> DAI
    #         # [
    #         #     to_bytes("0xae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337", "bytes32"),
    #         #     1,
    #         #     2,
    #         #     0, # Entire amount from previous swap
    #         #     bytes()
    #         # ]
    #     ],
    #     [wrappedADaiAddress, daiLinearPoolAddress], # , env.tokens["DAI"].address
    #     [amount, 0] # ,0
    # )

    # env.tradingModule.executeTrade(4, trade, {"from": dai_Whale})

    # daiLinearPoolEnd = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][0]
    # daiPoolBalanceEnd = daiLinearPool[1]/1e18
    # aDaiPoolBalanceEnd = daiLinearPool[3]/1e18
    # bptPoolBalanceEnd = daiLinearPool[4]/1e18

    # daiBalanceAfterEntering = interface.IERC20(env.tokens["DAI"].address).balanceOf(env.tradingModule.address)/1e18
    # bb_a_daiBalanceAfterEntering = interface.IERC20(daiLinearPoolAddress).balanceOf(env.tradingModule.address)/1e18

    # bptProportionEnd = bb_a_daiBalanceAfterEntering/bptPoolBalance

    # if underlyingPoolProportion > upperTargetDaiLinearPool:
    #     assert bptProportionEnd > bptProportion
    # elif underlyingPoolProportion < lowerTargetDaiLinearPool:
    #     assert bptProportionEnd < bptProportion
    # else:
    #     assert bptProportionEnd == bptProportion

    
    # #vault2.getStrategyContext()["baseStrategy"]["vaultSettings"]


    # # usdcLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][1]
    # # usdtLinearPool = vault2.getStrategyContext()["oracleContext"]["underlyingPools"][2]


    # # env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": stablecoin_Whale})

    # # env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": dai_Whale.address})  
    # # env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": usdc_Whale.address})  
    
    # # primaryBorrowAmount = 15000e8
    # # depositAmount = 15000e18

    # # depositParams = get_deposit_params()
    # # maturity = env.notional.getActiveMarkets(2)[0][1]



    # # env.notional.enterVault.call(
    # #             dai_Whale,
    # #             vault2.address,
    # #             Wei(depositAmount),
    # #             Wei(maturity),
    # #             Wei(primaryBorrowAmount),
    # #             0,
    # #             depositParams,
    # #             {"from": dai_Whale, "value": Wei(0)}
    # #         )


