import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from scripts.common import (
    get_deposit_params, 
    get_updated_vault_settings, 
    get_deposit_trade_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

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
    depositAmount = 10e18
    primaryBorrowAmount = 5e8
    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        depositAmount,
        maturity1,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": 10e18}
    )
    env.whales["ETH"].transfer(accounts[0], 100e18)
    maturity2 = env.notional.getActiveMarkets(1)[1][1]
    env.notional.enterVault(
        accounts[0],
        vault.address,
        depositAmount,
        maturity2,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": accounts[0], "value": 10e18}
    )
    vaultState1 = env.notional.getVaultState(vault.address, maturity1)
    vaultState2 = env.notional.getVaultState(vault.address, maturity2)
    vaultAccount1 = env.notional.getVaultAccount(env.whales["ETH"], vault.address)
    vaultAccount2 = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount1["vaultShares"], rel=1e-5) == 1482554110
    assert vaultAccount1["vaultShares"] == vaultState1["totalVaultShares"]
    underlyingValue1 = vault.convertStrategyToUnderlying(env.whales["ETH"], vaultAccount1["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue1, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10
    assert pytest.approx(vaultAccount2["vaultShares"], rel=1e-5) == 1482707034
    assert vaultAccount2["vaultShares"] == vaultState2["totalVaultShares"]
    underlyingValue2 = vault.convertStrategyToUnderlying(accounts[0], vaultAccount2["vaultShares"], maturity2)
    assert pytest.approx(underlyingValue2, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    pass

def test_multiple_accounts_in_each_maturity_success(StratStableETHstETH):
    pass

def test_secondary_currency_trading_success(StratStableETHstETH):
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
        get_deposit_params(trade=get_deposit_trade_params(
            DEX_ID["CURVE"], 
            TRADE_TYPE["EXACT_IN_SINGLE"],
            5e18,
            Wei(5e6),
            bytes(0)
        )),
        {"from": env.whales["ETH"], "value": depositAmount}
    )

def test_leverage_ratio_too_high_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    primaryBorrowAmount = 60e8
    depositAmount = 10e18
    txn = env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        depositAmount,
        maturity,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": depositAmount}
    )
    assert txn.status.value == 0 # reverted

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
    txn = env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        depositAmount,
        maturity,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": depositAmount}
    )
    assert txn.status.value == 0 # reverted

def test_deposit_in_settlement_window_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    settlementPeriod = vault.getStrategyContext()["baseStrategy"]["settlementPeriodInSeconds"]
    sleepAmount = maturity - settlementPeriod + 1 - chain.time()
    chain.sleep(sleepAmount)
    chain.mine()
    txn = env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        depositAmount,
        maturity,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": depositAmount}
    )
    assert txn.status.value == 0 # reverted

def test_bpt_slippage_failure(StratStableETHstETH):
    pass
