
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.dex_lp.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    pool_share_too_high,
    ETHPrimaryContext
)
from tests.dex_lp.helpers import get_deposit_op

chain = Chain()

def test_single_maturity_low_leverage_success(StratCurveStableETHstETH):
    deposit(ETHPrimaryContext(*StratCurveStableETHstETH), [get_deposit_op(100e18, 150e8, accounts[0])])

def test_single_maturity_high_leverage_success(StratCurveStableETHstETH):
    deposit(ETHPrimaryContext(*StratCurveStableETHstETH), [get_deposit_op(20e18, 150e8, accounts[0])])

def test_multiple_maturities_low_leverage_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [get_deposit_op(100e18, 150e8, accounts[0]), get_deposit_op(100e18, 150e8, accounts[1], 1)]
    )

def test_multiple_maturities_high_leverage_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [get_deposit_op(20e18, 150e8, accounts[0]), get_deposit_op(20e18, 150e8, accounts[1], 1)]
    )

def test_multiple_accounts_in_each_maturity_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [
            get_deposit_op(20e18, 150e8, accounts[0]),
            get_deposit_op(20e18, 150e8, accounts[1]),
            get_deposit_op(20e18, 150e8, accounts[2], 1),
            get_deposit_op(20e18, 150e8, accounts[3], 1)
        ]
    )

def test_leverage_ratio_too_high_failure(StratCurveStableETHstETH):
    leverage_ratio_too_high(ETHPrimaryContext(*StratCurveStableETHstETH), 5e18, 150e8)

def test_pool_share_too_high(StratCurveStableETHstETH):
    pool_share_too_high(ETHPrimaryContext(*StratCurveStableETHstETH), 5e18, 150e8)
