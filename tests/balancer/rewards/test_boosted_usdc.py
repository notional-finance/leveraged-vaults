
import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import (
    get_deposit_params, 
    get_dynamic_trade_params,
    get_univ3_batch_data,
    get_redeem_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_reinvest_rewards_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    rewardAmount = Wei(50e18)
    env.tokens["BAL"].transfer(vault.address, rewardAmount, {"from": env.whales["BAL"]})

    dynamicTradeParams = "(uint16,uint8,uint32,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(dynamicTradeParams)
    assert vault.getStrategyContext()["baseStrategy"]["totalBPTHeld"] == 0
    vault.reinvestReward([eth_abi.encode_abi(
        [singleSidedRewardTradeParams],
        [[
            env.tokens["BAL"].address,
            env.tokens["USDC"].address,
            rewardAmount,
            [
                DEX_ID["UNISWAP_V3"],
                TRADE_TYPE["EXACT_IN_BATCH"],
                Wei(5e6),
                False,
                get_univ3_batch_data([
                    env.tokens["BAL"].address, 3000, env.tokens["WETH"].address, 500, env.tokens["USDC"].address
                ])
            ]
        ]]
    ), 0],
        {"from": accounts[1]}
    )
    assert pytest.approx(vault.getStrategyContext()["baseStrategy"]["totalBPTHeld"], rel=1e-2) == 333984721856280513865
