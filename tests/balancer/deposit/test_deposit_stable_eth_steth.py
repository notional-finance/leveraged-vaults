import pytest
import brownie
from brownie import accounts
from brownie.network.state import Chain
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.balancer.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high,
    ETHPrimaryContext
)
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
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [[100e18, 150e8, accounts[0], 0]]
    )

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [[20e18, 150e8, accounts[0], 0]]
    )

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [
            [100e18, 150e8, accounts[0], 0],
            [100e18, 150e8, accounts[1], 1]
        ]
    )

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [
            [20e18, 150e8, accounts[0], 0],
            [20e18, 150e8, accounts[1], 1]
        ]
    )

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [
            [20e18, 150e8, accounts[0], 0],
            [20e18, 150e8, accounts[1], 0],
            [20e18, 150e8, accounts[2], 1],
            [20e18, 150e8, accounts[3], 1]
        ]
    )

@pytest.mark.skip
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

@pytest.mark.skip
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
    leverage_ratio_too_high(ETHPrimaryContext(*StratStableETHstETH), 5e18, 150e8)

def test_balancer_share_too_high(StratStableETHstETH):
    balancer_share_too_high(ETHPrimaryContext(*StratStableETHstETH), 5e18, 150e8)
