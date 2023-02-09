
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high,
    ETHPrimaryContext
)

chain = Chain()

def test_single_maturity_low_leverage_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [[100e18, 150e8, accounts[0], 0, None]]
    )

def test_single_maturity_high_leverage_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [[20e18, 150e8, accounts[0], 0, None]]
    )

def test_multiple_maturities_low_leverage_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [
            [100e18, 150e8, accounts[0], 0, None],
            [100e18, 150e8, accounts[1], 1, None]
        ]
    )

def test_multiple_maturities_high_leverage_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [
            [20e18, 150e8, accounts[0], 0, None],
            [20e18, 150e8, accounts[1], 1, None]
        ]
    )

def test_multiple_accounts_in_each_maturity_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [
            [20e18, 150e8, accounts[0], 0, None],
            [20e18, 150e8, accounts[1], 0, None],
            [20e18, 150e8, accounts[2], 1, None],
            [20e18, 150e8, accounts[3], 1, None]
        ]
    )
