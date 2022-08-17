import pytest
from brownie import ZERO_ADDRESS, Wei
from tests.fixtures import *
from tests.balancer.helpers import get_metastable_amounts
from scripts.common import (
    DEX_ID,
    TRADE_TYPE,
    get_univ3_single_data,
    get_univ3_batch_data
)

chain = Chain()

def test_claim_rewards_success(StratStableETHstETH):
    pass

def test_reinvest_rewards_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    rewardAmount = Wei(50e18)
    env.tokens["BAL"].transfer(vault.address, rewardAmount, {"from": env.whales["BAL"]})

    dynamicTradeParams = "(uint16,uint8,uint32,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(dynamicTradeParams)
    balanced2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(vault.getStrategyContext()["poolContext"], rewardAmount)
    vault.reinvestReward([eth_abi.encode_abi(
        [balanced2TokenRewardTradeParams],
        [[
            [
                env.tokens["BAL"].address,
                ZERO_ADDRESS,
                primaryAmount,
                [
                    DEX_ID["UNISWAP_V3"],
                    TRADE_TYPE["EXACT_IN_SINGLE"],
                    Wei(5e6),
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
                    Wei(5e6),
                    False,
                    get_univ3_batch_data([
                        env.tokens["BAL"].address, 3000, env.tokens["WETH"].address, 500, env.tokens["wstETH"].address
                    ])
                ]
            ]
        ]]
    ), 0],
        {"from": env.whales["USDC"]}
    )
