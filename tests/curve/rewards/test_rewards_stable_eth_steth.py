import json
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.balancer.helpers import get_metastable_amounts
from tests.balancer.acceptance import ETHPrimaryContext, claim_rewards, reinvest_reward
from scripts.common import (
    set_dex_flags,
    set_trade_type_flags,
    DEX_ID, 
    TRADE_TYPE
)
from tests.zeroex.helpers import load_test_data, save_test_data, fetch_0x_data

chain = Chain()

def test_claim_rewards(StratCurveStableETHstETH):
    claim_rewards(ETHPrimaryContext(*StratCurveStableETHstETH), 
        50e18,
        100e8, 
        accounts[0],
        {
            "CRV": 45802886784668566,
            "CVX": 1215280544308564,
            "LDO": 52497253657367505310
        }
    )

def test_reinvest_reward(StratCurveStableETHstETH):
    context = ETHPrimaryContext(*StratCurveStableETHstETH)
    env = context.env
    rewardAmount = Wei(10000e18)
    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    proportional2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(context.vault.getStrategyContext()["poolContext"], rewardAmount)
    poolClaimBefore = context.vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"]
    rewardParams = [eth_abi.encode_abi(
        [proportional2TokenRewardTradeParams],
        [[
            [
                env.tokens["CRV"].address,
                ZERO_ADDRESS,
                primaryAmount,
                [
                    DEX_ID["CURVE"],
                    TRADE_TYPE["EXACT_IN_SINGLE"],
                    0,
                    False,
                    bytes()
                ]
            ],
            [
                env.tokens["CRV"].address,
                env.tokens["stETH"].address,
                secondaryAmount,
                [
                    DEX_ID["CURVE"],
                    TRADE_TYPE["EXACT_IN_BATCH"],
                    0, #Wei(0.05e18), # static slippage
                    False,
                    bytes()
                ]
            ]
        ]]
    ), 0]

    env.tokens["CRV"].transfer(env.tradingModule.address, rewardAmount, {"from": env.whales["CRV"]})
    env.tradingModule.setTokenPermissions(
        env.tradingModule,
        env.tokens["CRV"].address,
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})
    trade = [
        TRADE_TYPE["EXACT_IN_BATCH"],
        env.tokens["CRV"].address,
        env.tokens["stETH"].address,
        secondaryAmount,
        0,
        chain.time() + 20000,
        bytes()
    ]
    with open("abi/CurveExchangeContract.json", "r") as f:
        abi = json.load(f)
    router = Contract.from_abi("CurveExchangeContract", "0x99a58482BD75cbab83b27EC03CA68fF489b5788f", abi)
    assert 1 == 2
    env.tradingModule.executeTrade(DEX_ID["CURVE"], trade, {"from": env.notional.owner()})

    #reinvest_reward(context, accounts[0], "CRV", rewardAmount, rewardParams, poolClaimBefore, 200916107796947076)
