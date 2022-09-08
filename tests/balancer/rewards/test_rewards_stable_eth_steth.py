import pytest
from brownie import ZERO_ADDRESS, Wei, accounts
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, get_metastable_amounts
from scripts.common import get_univ3_single_data, get_univ3_batch_data, DEX_ID, TRADE_TYPE

chain = Chain()

def test_claim_rewards_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 100e8
    depositAmount = 50e18
    enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    chain.sleep(3600 * 24 * 365)
    chain.mine()
    feeReceiver = vault.getStrategyContext()["baseStrategy"]["feeReceiver"]
    feePercentage = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]["feePercentage"] / 1e2
    assert env.tokens["BAL"].balanceOf(vault.address) == 0
    assert env.tokens["AURA"].balanceOf(vault.address) == 0
    assert env.tokens["BAL"].balanceOf(feeReceiver) == 0
    assert env.tokens["AURA"].balanceOf(feeReceiver) == 0
    vault.claimRewardTokens({"from": accounts[1]})
    assert pytest.approx(env.tokens["BAL"].balanceOf(vault.address), rel=1e-2) == 7724567060268075278
    assert pytest.approx(env.tokens["AURA"].balanceOf(vault.address), rel=1e-2) == 29384253097259758357
    # Test profit skimming
    assert pytest.approx(
        env.tokens["BAL"].balanceOf(feeReceiver) / (
            env.tokens["BAL"].balanceOf(vault.address) + env.tokens["BAL"].balanceOf(feeReceiver)) * 100,
        rel=1e-3
    ) == feePercentage
    assert pytest.approx(
        env.tokens["AURA"].balanceOf(feeReceiver) / (
            env.tokens["AURA"].balanceOf(vault.address) + env.tokens["AURA"].balanceOf(feeReceiver)) * 100,
        rel=1e-3
    ) == feePercentage

def test_reinvest_rewards_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    rewardAmount = Wei(50e18)
    env.tokens["BAL"].transfer(vault.address, rewardAmount, {"from": env.whales["BAL"]})

    dynamicTradeParams = "(uint16,uint8,uint32,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(dynamicTradeParams)
    balanced2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(vault.getStrategyContext()["poolContext"], rewardAmount)
    assert vault.getStrategyContext()["baseStrategy"]["totalBPTHeld"] == 0
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
        {"from": accounts[1]}
    )
    assert pytest.approx(vault.getStrategyContext()["baseStrategy"]["totalBPTHeld"], rel=1e-2) == 216521031523390134
