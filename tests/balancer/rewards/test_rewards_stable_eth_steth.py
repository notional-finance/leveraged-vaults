from brownie import ZERO_ADDRESS, Wei, accounts
from tests.fixtures import *
from tests.balancer.helpers import get_metastable_amounts
from tests.balancer.acceptance import ETHPrimaryContext, claim_rewards, reinvest_reward
from scripts.common import (
    get_univ3_single_data, 
    get_univ3_batch_data, 
    DEX_ID, 
    TRADE_TYPE
)

chain = Chain()

def test_claim_rewards(StratStableETHstETH):
    claim_rewards(ETHPrimaryContext(*StratStableETHstETH), 
        50e18,
        100e8, 
        accounts[0],
        {
            "BAL": 140021066496559459622,
            "AURA": 510423166313462670862
        }
    )

def test_reinvest_reward(StratStableETHstETH):
    context = ETHPrimaryContext(*StratStableETHstETH)
    env = context.env
    rewardAmount = Wei(50e18)
    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    balanced2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(context.vault.getStrategyContext()["poolContext"], rewardAmount)
    bptBefore = context.vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalBPTHeld"]
    rewardParams = [eth_abi.encode_abi(
        [balanced2TokenRewardTradeParams],
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

    reinvest_reward(context, accounts[0], rewardAmount, rewardParams, bptBefore, 209476561588413989)