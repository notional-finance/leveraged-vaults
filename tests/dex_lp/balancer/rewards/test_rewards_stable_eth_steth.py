from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.dex_lp.helpers import get_metastable_amounts
from tests.dex_lp.acceptance import ETHPrimaryContext, claim_rewards, reinvest_reward
from scripts.common import (
    get_univ3_single_data, 
    get_univ3_batch_data, 
    set_dex_flags,
    set_trade_type_flags,
    DEX_ID, 
    TRADE_TYPE
)
from tests.zeroex.helpers import load_test_data, save_test_data, fetch_0x_data

chain = Chain()

def test_claim_rewards(StratStableETHstETH):
    claim_rewards(ETHPrimaryContext(*StratStableETHstETH), 
        50e18,
        100e8, 
        accounts[0],
        {
            "BAL": 13123815655385993316,
            "AURA": 450315930428330847117
        }
    )

def test_reinvest_reward(StratStableETHstETH):
    context = ETHPrimaryContext(*StratStableETHstETH)
    env = context.env
    rewardAmount = Wei(50e18)
    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    proportional2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(context.vault.getStrategyContext()["poolContext"], rewardAmount)
    bptBefore = context.vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"]
    rewardParams = [eth_abi.encode_abi(
        [proportional2TokenRewardTradeParams],
        [[
            [
                env.tokens["BAL"].address,
                ZERO_ADDRESS,
                primaryAmount,
                [
                    DEX_ID["UNISWAP_V3"],
                    TRADE_TYPE["EXACT_IN_SINGLE"],
                    0,
                    False,
                    get_univ3_single_data(3000)
                ]
            ],
            [
                env.tokens["BAL"].address,
                env.tokens["wstETH"].address,
                secondaryAmount,
                [
                    DEX_ID["UNISWAP_V3"],
                    TRADE_TYPE["EXACT_IN_BATCH"],
                    Wei(0.05e18), # static slippage
                    False,
                    get_univ3_batch_data([
                        env.tokens["BAL"].address, 3000, env.tokens["WETH"].address, 500, env.tokens["wstETH"].address
                    ])
                ]
            ]
        ]]
    ), 0]

    reinvest_reward(context, accounts[0], "BAL", rewardAmount, rewardParams, bptBefore, 200916107796947076)

def test_reinvest_0x_trade(StratStableETHstETH, request):
    context = ETHPrimaryContext(*StratStableETHstETH)
    env = context.env
    rewardAmount = Wei(50e18)
    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    proportional2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(context.vault.getStrategyContext()["poolContext"], rewardAmount)

    testData = load_test_data(request.node.name)
    if env.forkBlockNumber > testData["blockNumber"]:
        ethTradeData = fetch_0x_data(
            env.tokens["BAL"],
            "ETH",
            primaryAmount,
            0.3
        )
        wstETHTradeData = fetch_0x_data(
            env.tokens["BAL"],
            env.tokens["wstETH"],
            secondaryAmount,
            0.3
        )
        save_test_data(request.node.name, env.forkBlockNumber, [ethTradeData, wstETHTradeData])
    else:
        ethTradeData = testData["params"][0]
        wstETHTradeData = testData["params"][1]

    bptBefore = context.vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"]
    rewardParams = [eth_abi.encode_abi(
        [proportional2TokenRewardTradeParams],
        [[
            [
                env.tokens["BAL"].address,
                ZERO_ADDRESS,
                primaryAmount,
                [
                    DEX_ID["ZERO_EX"],
                    TRADE_TYPE["EXACT_IN_SINGLE"],
                    0,
                    False,
                    to_bytes(ethTradeData, "bytes")
                ]
            ],
            [
                env.tokens["BAL"].address,
                env.tokens["wstETH"].address,
                secondaryAmount,
                [
                    DEX_ID["ZERO_EX"],
                    TRADE_TYPE["EXACT_IN_SINGLE"],
                    0,
                    False,
                    to_bytes(wstETHTradeData, "bytes")
                ]
            ]
        ]]
    ), 0]

    reinvest_reward(context, accounts[0], "BAL", rewardAmount, rewardParams, bptBefore, 200823932438657761, True) # shouldRevert = True

    # Give vault permission to sell wstETH
    env.tradingModule.setTokenPermissions(
        context.vault, 
        env.tokens["BAL"].address, 
        [True, set_dex_flags(0, ZERO_EX=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    reinvest_reward(context, accounts[0], "BAL", rewardAmount, rewardParams, bptBefore, 200823932438657761)
