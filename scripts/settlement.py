from brownie import (
    Contract, accounts, interface, MetaStable2TokenAuraVault, MetaStable2TokenAuraHelper, TradingModule,
    MockAggregator
)
from scripts.common import get_dynamic_trade_params, get_redeem_params, get_univ3_single_data, DEX_ID, TRADE_TYPE

def main():
    maturity = 1664064000
    vault = Contract.from_abi("MetaStableVault", "0xE767769b639Af18dbeDc5FB534E263fF7BE43456", MetaStable2TokenAuraVault.abi)
    notional = interface.NotionalProxy("0xD8229B55bD73c61D840d339491219ec6Fa667B0a")
    deployer = accounts.load("GOERLI_DEPLOYER")
    #MetaStable2TokenAuraHelper.deploy({"from": deployer})
    #newImpl = MetaStable2TokenAuraVault.deploy(
    #    notional.address,
    #    [
    #        "0x69232d11F36C17813C1B01ed73d6a4841a205dfa", #self.mockAuraBooster.address,
    #        [
    #            1,
    #            "0x945a00e88c662886241ce93d333009bee2b3df3f0002000000000000000001c2", #self.metaStablePoolId,
    #            "0x6AEbe2d1e94504079702fF1AEA16975dADf24cD3", #self.metaStableGauge.address,
    #            "0xd250e8FB009Dc1783d121A48B619bEAA34c4913B", #self.tradingModule.address,
    #            3600 * 24 * 7,
    #            "0x8638f94155c333fd7087c012Dc51B0528bb06035" # Treasury manager
    #        ]
    #    ],
    #    {"from": deployer}
    #)
    #settingData = vault.setStrategyVaultSettings.encode_input(
    #    (100000000000000000000, 60, 5000000, 10000000, 10000000, 5000000, 10000, 6000, 360, 360, 10000, 500)
    #)
    #vault.upgradeToAndCall("0x5191a9843Ccb9B9C0cA1Bf55e7f06b9F124dfBf3", settingData, {"from": notional.owner()})

    balancer = interface.IBalancerVault("0xBA12222222228d8Ba445958a75a0704d566BF2C8")
    #tradingModule = Contract.from_abi("TradingModule", "0xd250e8FB009Dc1783d121A48B619bEAA34c4913B", TradingModule.abi)
    #newTradingImpl = TradingModule.deploy(notional.address, tradingModule.address, {"from": deployer})
    #vault.upgradeTo(newImpl.address, {"from": notional.owner()})
    redeemParams = get_redeem_params(
        0, 0, get_dynamic_trade_params(
            DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 10e6, False, get_univ3_single_data(3000)
        )
    )
    oracle = MockAggregator.at("0x88903cC1257e29Cfe5Da778B92Bd3229317511F7")
    #oracle.setAnswer(484558631502, {"from": deployer})
    #vault.settleVaultPostMaturity(1664064000, 298326418, redeemParams, {"from": notional.owner()})