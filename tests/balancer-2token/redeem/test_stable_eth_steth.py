import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from scripts.common import (
    get_deposit_params, 
    get_secondary_trade_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_full_redemption_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        depositAmount,
        maturity,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": depositAmount}
    )
    vaultAccount = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    vaultShares = vaultAccount["vaultShares"]
    primaryAmountBefore = env.whales["ETH"].balance()
    env.notional.exitVault(
        env.whales["ETH"],
        vault.address,
        env.whales["ETH"],
        vaultShares,
        primaryBorrowAmount,
        0,
        get_redeem_params(0, 0, get_secondary_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )),
        {"from": env.whales["ETH"]}
    )
    primaryAmountAfter = env.whales["ETH"].balance()
    vaultAccount = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    vaultShares = vaultAccount["vaultShares"]
    assert vaultShares == 0
    assert pytest.approx(primaryAmountAfter - primaryAmountBefore, rel=5e-2) == 9978201005559637495

def test_single_maturity_partial_redemption_success(StratStableETHstETH):
    pass

def get_redeem_params(minPrimary, minSecondary, trade):
    return eth_abi.encode_abi(
        ['(uint32,uint256,uint256,bytes)'],
        [[
            0,
            Wei(minPrimary * 0.98),
            Wei(minSecondary * 0.98),
            trade
        ]]
    )
