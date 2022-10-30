import pytest
import brownie
from brownie import ZERO_ADDRESS, accounts
from brownie.network.state import Chain
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, check_invariant, get_expected_borrow_amount
from scripts.common import (
    get_deposit_params, 
    get_updated_vault_settings, 
    get_deposit_trade_params,
    set_dex_flags,
    set_trade_type_flags,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def get_expected_bpt_amount(env, vault, depositAmount, expectedBorrowAmount, primaryPercent=1):
    totalJoinAmount = depositAmount + expectedBorrowAmount
    primaryAmount = totalJoinAmount * primaryPercent
    undoCount = 0
    if primaryAmount > 0:
        env.whales["ETH"].transfer(vault, primaryAmount)
        undoCount += 1
    primaryAmountToSell = totalJoinAmount - primaryAmount
    secondaryAmount = 0
    if primaryAmountToSell > 0:
        env.whales["ETH"].transfer(env.tradingModule, primaryAmountToSell)
        env.tradingModule.setTokenPermissions(
            env.tradingModule, 
            ZERO_ADDRESS, 
            [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
            {"from": env.notional.owner()})
        trade = [
            TRADE_TYPE["EXACT_IN_SINGLE"], 
            ZERO_ADDRESS,
            env.tokens["wstETH"].address, 
            primaryAmountToSell, 
            0, 
            chain.time() + 20000, 
            eth_abi.encode_abi(
                ["(bytes32)"],
                [[to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32")]]
            )
        ]
        env.tradingModule.executeTrade(DEX_ID["BALANCER_V2"], trade, {"from": env.whales["ETH"]})
        secondaryAmount = env.tokens["wstETH"].balanceOf(env.tradingModule)
        env.tokens["wstETH"].transfer(vault, secondaryAmount, {"from": env.tradingModule})
        undoCount += 4
    expectedBPTAmount = vault.joinPoolAndStake.call(primaryAmount, secondaryAmount, 0) / 1e10
    chain.undo(undoCount)
    return expectedBPTAmount

def test_single_maturity_low_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount
    check_invariant(env, vault, [accounts[0]], [maturity])

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount
    check_invariant(env, vault, [accounts[0]], [maturity])

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18

    # account 1
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 2
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[1])
    vaultAccount = env.notional.getVaultAccount(accounts[1], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[1], vaultAccount["vaultShares"], maturity2)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18

    # account 1
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue1 = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue1, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 2
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[1])
    vaultAccount2 = env.notional.getVaultAccount(accounts[1], vault.address)
    assert pytest.approx(vaultAccount2["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue2 = vault.convertStrategyToUnderlying(accounts[1], vaultAccount2["vaultShares"], maturity2)
    assert pytest.approx(underlyingValue2, rel=5e-3) == depositAmount + expectedBorrowAmount

    check_invariant(env, vault, [accounts[0], accounts[1]], [maturity1, maturity2])

def test_multiple_accounts_in_each_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18

    # account 1
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 2
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[1])
    vaultAccount = env.notional.getVaultAccount(accounts[1], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[1], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 3
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    maturity2 = enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[2])
    vaultAccount = env.notional.getVaultAccount(accounts[2], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[2], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    # account 4
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 1, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, 1, 1, depositAmount, primaryBorrowAmount, accounts[3])
    vaultAccount = env.notional.getVaultAccount(accounts[3], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[3], vaultAccount["vaultShares"], maturity1)
    assert pytest.approx(underlyingValue, rel=5e-3) == depositAmount + expectedBorrowAmount

    check_invariant(env, vault, [accounts[0], accounts[1], accounts[2], accounts[3]], [maturity1, maturity2])

def test_secondary_currency_trading_unwrapped_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount, 0.5)
    totalUnderlyingAmount = depositAmount + expectedBorrowAmount
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["CURVE"],  TRADE_TYPE["EXACT_IN_SINGLE"], (totalUnderlyingAmount) / 2, 5e6, True, bytes(0)
    ))
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0], False, depositParams)
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-3) == totalUnderlyingAmount
    check_invariant(env, vault, [accounts[0]], [maturity])

def test_secondary_currency_trading_wrapped_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    expectedBPTAmount = get_expected_bpt_amount(env, mock, depositAmount, expectedBorrowAmount, 0.5)
    totalUnderlyingAmount = depositAmount + expectedBorrowAmount
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["BALANCER_V2"],  TRADE_TYPE["EXACT_IN_SINGLE"], totalUnderlyingAmount / 2, 5e6, False, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32")]]
        )
    ))
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0], False, depositParams)
    vaultAccount = env.notional.getVaultAccount(accounts[0], vault.address)
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == expectedBPTAmount
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    underlyingValue = vault.convertStrategyToUnderlying(accounts[0], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-3) == totalUnderlyingAmount
    check_invariant(env, vault, [accounts[0]], [maturity])

def test_leverage_ratio_too_high_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 90e8
    depositAmount = 10e18
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0], True)

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
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    with brownie.reverts():
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0], True)
