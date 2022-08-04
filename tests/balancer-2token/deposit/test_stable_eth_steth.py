import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from tests.fixtures import *
from scripts.common import get_deposit_params, get_updated_vault_settings

def test_single_maturity_low_leverage_success(StratStableETHstETH):
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
    vaultState = env.notional.getVaultState(vault.address, maturity)
    vaultAccount = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    assert vaultState["totalfCash"] == vaultAccount["fCash"]
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 1482554109
    assert vaultAccount["vaultShares"] == vaultState["totalVaultShares"]
    assert vaultAccount["vaultShares"] == vaultState["totalStrategyTokens"]
    underlyingValue = vault.convertStrategyToUnderlying(env.whales["ETH"], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    primaryBorrowAmount = 40e8
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
    vaultState = env.notional.getVaultState(vault.address, maturity)
    vaultAccount = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    assert vaultState["totalfCash"] == vaultAccount["fCash"]
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 4922602638
    assert vaultAccount["vaultShares"] == vaultState["totalVaultShares"]
    assert vaultAccount["vaultShares"] == vaultState["totalStrategyTokens"]
    underlyingValue = vault.convertStrategyToUnderlying(env.whales["ETH"], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity1 = env.notional.getActiveMarkets(1)[0][1]
    maturity2 = env.notional.getActiveMarkets(1)[1][1]
    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        10e18,
        maturity1,
        5e8,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": 10e18}
    )
    env.whales["ETH"].transfer(accounts[0], 100e18)
    env.notional.enterVault(
        accounts[0],
        vault.address,
        10e18,
        maturity2,
        5e8,
        0,
        get_deposit_params(),
        {"from": accounts[0], "value": 10e18}
    )

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    pass

def test_multiple_accounts_in_each_maturity_success(StratStableETHstETH):
    pass

def test_secondary_currency_trading_success(StratStableETHstETH):
    pass

@pytest.mark.skip
def test_leverage_ratio_too_high_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    primaryBorrowAmount = 60e8
    depositAmount = 10e18
    with brownie.reverts("Insufficient Collateral"):
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

def test_balancer_share_too_high_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxBalancerPoolShare=0),
        {"from": env.notional.owner()}
    )
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    with brownie.reverts():
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

def test_deposit_in_settlement_window_failure(StratStableETHstETH):
    pass

def test_bpt_slippage_failure(StratStableETHstETH):
    pass
