from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.balancer.helpers import get_metastable_amounts
from tests.balancer.acceptance import ETHPrimaryContext, claim_rewards, reinvest_reward
from scripts.common import (
    get_univ3_single_data, 
    get_univ3_batch_data, 
    set_dex_flags,
    set_trade_type_flags,
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
            "BAL": 150865160011918313877,
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

    reinvest_reward(context, accounts[0], rewardAmount, rewardParams, bptBefore, 200916107796947076)

def test_reinvest_0x_trade(StratStableETHstETH):
    context = ETHPrimaryContext(*StratStableETHstETH)
    env = context.env
    rewardAmount = Wei(50e18)
    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    balanced2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(context.vault.getStrategyContext()["poolContext"], rewardAmount)

    # To generate this trade data after advancing the block number
    # Call https://api.0x.org/swap/v1/quote?sellToken=0xba100000625a3754423978a60c9317c58a424e3D&buyToken=ETH&sellAmount=19857623293043160000&slippagePercentage=0.05
    ethTradeData = "0x803ba26d00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000011394732cc15c33c00000000000000000000000000000000000000000000000000131a7b1b964a0680000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002bba100000625a3754423978a60c9317c58a424e3d000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000009335d7c5af63a1f321"
    # Call https://api.0x.org/swap/v1/quote?sellToken=0xba100000625a3754423978a60c9317c58a424e3D&buyToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&sellAmount=30142376706956840000&slippagePercentage=0.05
    stETHTradeData = "0x6af479b20000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000001a24f3be9f02bcc4000000000000000000000000000000000000000000000000001a97e1b4ccd5c0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042ba100000625a3754423978a60c9317c58a424e3d000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f47f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000fc4a2bfe6c63a1f33d"
    bptBefore = context.vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalBPTHeld"]
    rewardParams = [eth_abi.encode_abi(
        [balanced2TokenRewardTradeParams],
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
                    to_bytes(stETHTradeData, "bytes")
                ]
            ]
        ]]
    ), 0]

    reinvest_reward(context, accounts[0], rewardAmount, rewardParams, bptBefore, 209476561588413989, True) # shouldRevert = True

    # Give vault permission to sell wstETH
    env.tradingModule.setTokenPermissions(
        context.vault, 
        env.tokens["BAL"].address, 
        [True, set_dex_flags(0, ZERO_EX=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    reinvest_reward(context, accounts[0], rewardAmount, rewardParams, bptBefore, 209476561588413989)
