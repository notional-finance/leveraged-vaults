import pytest
import brownie
from brownie import accounts
from brownie.network.state import Chain
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.balancer.acceptance import deposit_test, ETHPrimaryContext
from tests.balancer.helpers import (
    enterMaturity,
    snapshot_invariants,
    check_invariants, 
    get_expected_borrow_amount, 
    get_expected_bpt_amount
)
from scripts.common import (
    get_deposit_params, 
    get_updated_vault_settings, 
    get_deposit_trade_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_low_leverage_success(StratStableETHstETH):
    deposit_test(ETHPrimaryContext(*StratStableETHstETH), 100e18, 150e8)

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 20e18
    maturity1 = env.notional.getActiveMarkets(currencyId)[0][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[1][1]
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    snapshot = snapshot_invariants(env, vault, [maturity1, maturity2])
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount
    check_invariants(env, vault, [accounts[0]], [maturity1, maturity2], snapshot)

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 100e18
    maturity1 = env.notional.getActiveMarkets(currencyId)[0][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[1][1]
    snapshot = snapshot_invariants(env, vault, [maturity1, maturity2])

    # account 1
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 2
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity2, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity2, depositAmount, primaryBorrowAmount, accounts[1])
    vaultAccount = env.notional.getVaultAccount(accounts[1], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[1], vaultAccount["vaultShares"], maturity2)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    check_invariants(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2], snapshot)

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 20e18
    maturity1 = env.notional.getActiveMarkets(currencyId)[0][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[1][1]
    snapshot = snapshot_invariants(env, vault, [maturity1, maturity2])

    # account 1
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue1 = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue1, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 2
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity2, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity2, depositAmount, primaryBorrowAmount, accounts[1])
    vaultAccount2 = env.notional.getVaultAccount(accounts[1], vault.address)
    assert pytest.approx(vaultAccount2["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue2 = vault.convertStrategyToUnderlying(accounts[1], vaultAccount2["vaultShares"], maturity2)
    assert pytest.approx(underlyingValue2, rel=5e-3) == depositAmount + expectedBorrowAmount

    check_invariants(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2], snapshot)

def test_multiple_accounts_in_each_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 20e18
    maturity1 = env.notional.getActiveMarkets(currencyId)[0][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[1][1]
    snapshot = snapshot_invariants(env, vault, [maturity1, maturity2])

    # account 1
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 2
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[1])
    vaultAccount = env.notional.getVaultAccount(accounts[1], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[1], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 3
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity2, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity2, depositAmount, primaryBorrowAmount, accounts[2])
    vaultAccount = env.notional.getVaultAccount(accounts[2], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[2], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 4
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity2, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturity2, depositAmount, primaryBorrowAmount, accounts[3])
    vaultAccount = env.notional.getVaultAccount(accounts[3], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[3], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    check_invariants(env, vault, [accounts[0], accounts[1], accounts[2], accounts[3]], [maturity1, maturity2], snapshot)

def test_secondary_currency_trading_unwrapped_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 20e18
    maturity1 = env.notional.getActiveMarkets(currencyId)[0][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[1][1]
    snapshot = snapshot_invariants(env, vault, [maturity1, maturity2])
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount, 0.5)
    totalUnderlyingAmount = depositAmount + expectedBorrowAmount
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["CURVE"],  TRADE_TYPE["EXACT_IN_SINGLE"], (totalUnderlyingAmount) / 2, 5e6, True, bytes(0)
    ))
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[0], False, depositParams)
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == totalUnderlyingAmount
    check_invariants(env, vault, [accounts[0]], [maturity1, maturity2], snapshot)

def test_secondary_currency_trading_wrapped_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 20e18
    maturity1 = env.notional.getActiveMarkets(currencyId)[0][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[1][1]
    snapshot = snapshot_invariants(env, vault, [maturity1, maturity2])
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount, 0.5)
    totalUnderlyingAmount = depositAmount + expectedBorrowAmount
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["BALANCER_V2"],  TRADE_TYPE["EXACT_IN_SINGLE"], totalUnderlyingAmount / 2, 5e6, False, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32")]]
        )
    ))
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[0], False, depositParams)
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBPTAmount
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == totalUnderlyingAmount
    check_invariants(env, vault, [accounts[0]], [maturity1, maturity2], snapshot)

def test_leverage_ratio_too_high_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 5e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, accounts[0], True)

def test_balancer_share_too_high_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
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
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 20e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    with brownie.reverts():
        enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, accounts[0], True)
