import pytest
import brownie
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, check_invariant
from scripts.common import (
    get_deposit_params, 
    get_updated_vault_settings, 
    get_deposit_trade_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_low_leverage_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 1491399022
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10
    check_invariant(env, vault, [accounts[0]], [maturity])

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 4962562414
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10
    check_invariant(env, vault, [accounts[0]], [maturity])

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount1 = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount1["vaultShares"], rel=1e-5) == 1491399014
    underlyingValue1 = vault.convertStrategyToUnderlying(accounts[0], vaultAccount1["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue1, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[1])
    vaultAccount2 = env.notional.getVaultAccount(accounts[1], vault.address)
    assert pytest.approx(vaultAccount2["vaultShares"], rel=1e-5) == 1489827320
    underlyingValue2 = vault.convertStrategyToUnderlying(accounts[1], vaultAccount2["vaultShares"], maturity2)
    assert pytest.approx(underlyingValue2, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[1])
    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])

def test_multiple_accounts_in_each_maturity_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[1])
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[2])
    enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[3])
    check_invariant(env, vault, [accounts[0], accounts[1], accounts[2], accounts[3]], [maturity1, maturity2])

def test_secondary_currency_trading_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["CURVE"], 
        TRADE_TYPE["EXACT_IN_SINGLE"],
        5e18,
        5e6,
        True,
        bytes(0)
    ))
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0], depositParams)
    check_invariant(env, vault, [accounts[0]], [maturity])

def test_leverage_ratio_too_high_failure(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 90e8
    depositAmount = 10e18
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0], True)

def test_balancer_share_too_high_failure(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    # Only Notional owner can change settings
    with brownie.reverts():
        vault.setStrategyVaultSettings.call(
            get_updated_vault_settings(settings, maxBalancerPoolShare=0),
            {"from": accounts[0]}
        )
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxBalancerPoolShare=0),
        {"from": env.notional.owner()}
    )
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    with brownie.reverts():
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0], True)
