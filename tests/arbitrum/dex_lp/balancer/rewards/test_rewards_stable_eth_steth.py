from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.arbitrum.dex_lp.helpers import get_metastable_amounts
from tests.arbitrum.dex_lp.acceptance import ETHPrimaryContext, claim_rewards, reinvest_reward
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

def test_claim_rewards(ArbStratStableETHstETH):
    (env, vault, mock) = ArbStratStableETHstETH
    whale = accounts.at("0xc948eb5205bde3e18cac4969d6ad3a56ba7b2347", force=True)
    env.notional.batchBalanceAction(whale, [[4, 1, Wei(9e18), 0, False, True]], {"from": whale, "value": Wei(9e18)})
    claim_rewards(ETHPrimaryContext(*ArbStratStableETHstETH), 
        1e18,
        2e8, 
        accounts[0],
        {
            "BAL": 101286142799343346,
            "AURA": 304456240885350537
        }
    )

def test_reinvest_0x_trade(ArbStratStableETHstETH, request):
    context = ETHPrimaryContext(*ArbStratStableETHstETH)
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

    reinvest_reward(context, accounts[0], "BAL", rewardAmount, rewardParams, bptBefore, 107818923229042776, True) # shouldRevert = True

    # Give vault permission to sell wstETH
    env.tradingModule.setTokenPermissions(
        context.vault, 
        env.tokens["BAL"].address, 
        [True, set_dex_flags(0, ZERO_EX=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})

    reinvest_reward(context, accounts[0], "BAL", rewardAmount, rewardParams, bptBefore, 107818923229042776)
