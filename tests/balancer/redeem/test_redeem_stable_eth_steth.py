import pytest
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import check_invariant, check_account, enterMaturity, exitVaultPercent
from scripts.common import get_dynamic_trade_params, get_redeem_params, DEX_ID, TRADE_TYPE

chain = Chain()

def test_single_maturity_full_redemption_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    primaryAmountBefore = accounts[0].balance()
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    exitVaultPercent(env, vault, accounts[0], 1.0, redeemParams)
    check_invariant(env, vault, [accounts[0]], [maturity])
    check_account(env, vault, accounts[0], 0, 0)
    assert pytest.approx(accounts[0].balance() - primaryAmountBefore, rel=5e-2) == depositAmount
    
def test_single_maturity_partial_redemption_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])

    vaultSharesBefore =  env.notional.getVaultAccount(accounts[0], vault.address)["vaultShares"]
    primaryAmountBefore = accounts[0].balance()
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, accounts[0], 0.5, redeemParams)
    check_invariant(env, vault, [accounts[0]], [maturity])
    check_account(env, vault, accounts[0], vaultSharesBefore - sharesRedeemed, primaryBorrowAmount - fCashRepaid)
    assert pytest.approx(accounts[0].balance() - primaryAmountBefore, rel=5e-2) == depositAmount * 0.5

    exitVaultPercent(env, vault, accounts[0], 1, redeemParams)
    check_invariant(env, vault, [accounts[0]], [maturity])
    check_account(env, vault, accounts[0], 0, 0)
    assert pytest.approx(accounts[0].balance() - primaryAmountBefore, rel=5e-2) == depositAmount

def test_multiple_maturities_full_redemption_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    depositAmount = 10e18
    primaryBorrowAmount = 5e8
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[1])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    primaryAmountBefore1 = accounts[0].balance()
    primaryAmountBefore2 = accounts[1].balance()
    exitVaultPercent(env, vault, accounts[0], 1, redeemParams)
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])
    check_account(env, vault, accounts[0], 0, 0)
    assert pytest.approx(accounts[0].balance() - primaryAmountBefore1, rel=5e-2) == depositAmount
    exitVaultPercent(env, vault, accounts[1], 1, redeemParams)
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])
    check_account(env, vault, accounts[1], 0, 0)
    assert pytest.approx(accounts[0].balance() - primaryAmountBefore2, rel=5e-2) == depositAmount

def test_multiple_maturities_partial_redemption_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    depositAmount = 10e18
    primaryBorrowAmount = 5e8
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[1])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    vaultSharesBefore1 =  env.notional.getVaultAccount(accounts[0], vault.address)["vaultShares"]
    vaultSharesBefore2 =  env.notional.getVaultAccount(accounts[1], vault.address)["vaultShares"]
    primaryAmountBefore1 = accounts[0].balance()
    primaryAmountBefore2 = accounts[1].balance()
    (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, accounts[0], 0.5, redeemParams)
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])
    check_account(env, vault, accounts[0], vaultSharesBefore1 - sharesRedeemed, primaryBorrowAmount - fCashRepaid)
    assert pytest.approx(accounts[0].balance() - primaryAmountBefore1, rel=5e-2) == depositAmount * 0.5
    (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, accounts[1], 0.5, redeemParams)
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])
    check_account(env, vault, accounts[1], vaultSharesBefore2 - sharesRedeemed, primaryBorrowAmount - fCashRepaid)
    assert pytest.approx(accounts[1].balance() - primaryAmountBefore2, rel=5e-2) == depositAmount * 0.5
    
    exitVaultPercent(env, vault, accounts[0], 1, redeemParams)
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])
    check_account(env, vault, accounts[0], 0, 0)
    assert pytest.approx(accounts[0].balance() - primaryAmountBefore1, rel=5e-2) == depositAmount
    exitVaultPercent(env, vault, accounts[1], 1, redeemParams)
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])
    check_account(env, vault, accounts[1], 0, 0)
    assert pytest.approx(accounts[1].balance() - primaryAmountBefore2, rel=5e-2) == depositAmount
