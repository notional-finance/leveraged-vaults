import pytest
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, get_metastable_amounts
from scripts.common import (
    get_univ3_single_data, 
    get_univ3_batch_data, 
    DEX_ID, 
    TRADE_TYPE,
    set_dex_flags,
    set_trade_type_flags
)

chain = Chain()

def test_claim_rewards_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 100e8
    depositAmount = 50e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, accounts[0])
    chain.sleep(3600 * 24 * 365)
    chain.mine()
    assert env.tokens["BAL"].balanceOf(vault.address) == 0
    assert env.tokens["AURA"].balanceOf(vault.address) == 0

    # Cannot claim without the proper role assigned
    with brownie.reverts():
        vault.claimRewardTokens.call({"from": accounts[1]})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["rewardReinvestment"], accounts[1], {"from": accounts[2]})
    vault.grantRole(vault.getRoles()["rewardReinvestment"], accounts[1], {"from": env.notional.owner()})
    
    txn = vault.claimRewardTokens({"from": accounts[1]})

    assert txn.return_value[0] == env.tokens["BAL"].balanceOf(vault.address)
    assert txn.return_value[1] == env.tokens["AURA"].balanceOf(vault.address)
    assert pytest.approx(env.tokens["BAL"].balanceOf(vault.address), rel=1e-2) == 82947726591360320852
    assert pytest.approx(env.tokens["AURA"].balanceOf(vault.address), rel=1e-2) == 305248161917312885590

def test_reinvest_rewards_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    rewardAmount = Wei(50e18)
    env.tokens["BAL"].transfer(vault.address, rewardAmount, {"from": env.whales["BAL"]})

    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    balanced2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(vault.getStrategyContext()["poolContext"], rewardAmount)
    bptBefore = vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalBPTHeld"]
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

    # Cannot reinvest without the proper role assigned
    with brownie.reverts():
        vault.reinvestReward.call(rewardParams, {"from": accounts[1]})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["rewardReinvestment"], accounts[1], {"from": accounts[2]})
    vault.grantRole(vault.getRoles()["rewardReinvestment"], accounts[1], {"from": env.notional.owner()})

    vault.reinvestReward(rewardParams, {"from": accounts[1]})

    bptAfter = vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalBPTHeld"]
    assert pytest.approx(bptAfter - bptBefore, rel=1e-2) == 209476561588413989
