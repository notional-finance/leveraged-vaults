import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, exitVaultPercent
from scripts.common import (
    get_deposit_params, 
    get_dynamic_trade_params,
    get_redeem_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_full_redemption_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    primaryAmountBefore = accounts[0].balance()
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    exitVaultPercent(env, vault, accounts[0], 1.0, redeemParams)
    primaryAmountAfter = accounts[0].balance()
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    vaultShares = vaultAccount["vaultShares"]
    assert vaultShares == 0
    assert pytest.approx(primaryAmountAfter - primaryAmountBefore, rel=5e-2) == depositAmount

def test_single_maturity_partial_redemption_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    vaultSharesBefore = vaultAccount["vaultShares"]
    primaryAmountBefore = accounts[0].balance()
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    exitVaultPercent(env, vault, accounts[0], 0.5, redeemParams)
    primaryAmountAfter = accounts[0].balance()
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert vaultAccount["vaultShares"] == vaultSharesBefore * 0.5
    assert pytest.approx(primaryAmountAfter - primaryAmountBefore, rel=5e-2) == depositAmount * 0.5
    assert vaultAccount['fCash'] == -primaryBorrowAmount * 0.5
    primaryAmountBefore = accounts[0].balance()
    exitVaultPercent(env, vault, accounts[0], 1, redeemParams)
    primaryAmountAfter = accounts[0].balance()
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert vaultAccount["vaultShares"] == 0
    assert pytest.approx(primaryAmountAfter - primaryAmountBefore, rel=5e-2) == depositAmount * 0.5
    assert vaultAccount['fCash'] == 0

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
        get_redeem_params(0, 0, get_dynamic_trade_params(
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
        get_redeem_params(0, 0, get_dynamic_trade_params(
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
