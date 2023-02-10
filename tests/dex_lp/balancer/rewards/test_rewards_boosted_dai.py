
import eth_abi
from brownie import Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.dex_lp.acceptance import DAIPrimaryContext, claim_rewards, reinvest_reward
from scripts.common import get_univ3_batch_data, DEX_ID, TRADE_TYPE

chain = Chain()

def test_claim_rewards_success(StratBoostedPoolDAIPrimary):
    claim_rewards(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        10000e18,
        5000e8, 
        accounts[0],
        {
            "BAL": 131970343996744098,
            "AURA": 500807534315721345
        }
    )

def test_reinvest_rewards_success(StratBoostedPoolDAIPrimary):
    context = DAIPrimaryContext(*StratBoostedPoolDAIPrimary)
    env = context.env
    rewardAmount = Wei(50e18)
    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    bptBefore = context.vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"]
    rewardParams = [eth_abi.encode_abi(
        [singleSidedRewardTradeParams],
        [[
            env.tokens["BAL"].address,
            env.tokens["DAI"].address,
            rewardAmount,
            [
                DEX_ID["UNISWAP_V3"],
                TRADE_TYPE["EXACT_IN_BATCH"],
                0,
                False,
                get_univ3_batch_data([
                    env.tokens["BAL"].address, 3000, env.tokens["WETH"].address, 500, env.tokens["DAI"].address
                ])
            ]
        ]]
    ), 0]

    reinvest_reward(context, accounts[0], "BAL", rewardAmount, rewardParams, bptBefore, 290374198729029913290)
