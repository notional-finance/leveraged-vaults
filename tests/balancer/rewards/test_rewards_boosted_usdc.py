
import pytest
import eth_abi
from brownie import Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import get_univ3_batch_data, DEX_ID, TRADE_TYPE

chain = Chain()

def test_claim_rewards_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    chain.sleep(3600 * 24 * 365)
    chain.mine()
    feeReceiver = vault.getStrategyContext()["baseStrategy"]["feeReceiver"]
    feePercentage = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]["feePercentage"] / 1e2
    assert env.tokens["BAL"].balanceOf(vault.address) == 0
    assert env.tokens["AURA"].balanceOf(vault.address) == 0
    assert env.tokens["BAL"].balanceOf(feeReceiver) == 0
    assert env.tokens["AURA"].balanceOf(feeReceiver) == 0
    vault.claimRewardTokens({"from": accounts[1]})
    assert pytest.approx(env.tokens["BAL"].balanceOf(vault.address), rel=1e-2) == 759444240330538290
    assert pytest.approx(env.tokens["AURA"].balanceOf(vault.address), rel=1e-2) == 2888848093557356931
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
