import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import (
    get_deposit_params, 
    get_secondary_trade_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_full_redemption_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, env.whales["ETH"])
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
    assert pytest.approx(primaryAmountAfter - primaryAmountBefore, rel=5e-2) == depositAmount

def test_single_maturity_partial_redemption_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, env.whales["ETH"])
    vaultAccount = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    vaultShares = vaultAccount["vaultShares"]
    vaultSharesBefore = vaultShares
    primaryAmountBefore = env.whales["ETH"].balance()
    env.notional.exitVault(
        env.whales["ETH"],
        vault.address,
        env.whales["ETH"],
        vaultShares / 2,
        primaryBorrowAmount / 2,
        0,
        get_redeem_params(0, 0, get_secondary_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )),
        {"from": env.whales["ETH"]}
    )
    primaryAmountAfter = env.whales["ETH"].balance()
    vaultAccount = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    vaultShares = vaultAccount["vaultShares"]
    assert vaultShares == vaultSharesBefore / 2
    assert pytest.approx(primaryAmountAfter - primaryAmountBefore, rel=5e-2) == depositAmount / 2
    fcashDebt = vaultAccount['fCash']
    assert fcashDebt == -primaryBorrowAmount / 2
    primaryAmountBefore = env.whales["ETH"].balance()
    env.notional.exitVault(
        env.whales["ETH"],
        vault.address,
        env.whales["ETH"],
        vaultShares,
        -fcashDebt,
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
    assert pytest.approx(primaryAmountAfter - primaryAmountBefore, rel=5e-2) == depositAmount / 2
    fcashDebt = vaultAccount['fCash']
    assert fcashDebt == 0

def test_multiple_maturities_full_redemption_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    depositAmount = 10e18
    primaryBorrowAmount = 5e8
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, env.whales["ETH"])
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount1 = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    vaultShares1 = vaultAccount1["vaultShares"]
    vaultAccount2 = env.notional.getVaultAccount(accounts[0], vault.address)
    vaultShares2 = vaultAccount2["vaultShares"]
    env.notional.exitVault(
        env.whales["ETH"],
        vault.address,
        env.whales["ETH"],
        vaultShares1,
        primaryBorrowAmount,
        0,
        get_redeem_params(0, 0, get_secondary_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )),
        {"from": env.whales["ETH"]}
    )
    env.notional.exitVault(
        accounts[0],
        vault.address,
        accounts[0],
        vaultShares2,
        primaryBorrowAmount,
        0,
        get_redeem_params(0, 0, get_secondary_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )),
        {"from": accounts[0]}
    )
    vaultState1 = env.notional.getVaultState(vault.address, maturity1)
    vaultState2 = env.notional.getVaultState(vault.address, maturity2)
    assert vaultState1["totalVaultShares"] == 0
    assert vaultState2["totalVaultShares"] == 0

def test_multiple_maturities_partial_redemption_success(StratStableETHstETH):
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
