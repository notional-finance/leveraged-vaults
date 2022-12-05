from brownie import accounts
from tests.fixtures import *
from tests.balancer.acceptance import (
    DAIPrimaryContext, 
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high
)

def test_single_maturity_low_leverage_success(StratBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        [[10000e18, 5000e8, accounts[0], 0, None]]
    )

def test_single_maturity_high_leverage_success(StratBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        [[10000e18, 40000e8, accounts[0], 0, None]]
    )

def test_multiple_maturities_low_leverage_success(StratBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        [
            [10000e18, 5000e8, accounts[0], 0, None],
            [10000e18, 5000e8, accounts[1], 1, None]
        ]
    )

def test_multiple_maturities_high_leverage_success(StratBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        [
            [10000e18, 40000e8, accounts[0], 0, None],
            [10000e18, 40000e8, accounts[1], 1, None]
        ]
    )

def test_multiple_accounts_in_each_maturity_success(StratBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        [
            [10000e18, 40000e8, accounts[0], 0, None],
            [10000e18, 40000e8, accounts[1], 0, None],
            [10000e18, 40000e8, accounts[2], 1, None],
            [10000e18, 40000e8, accounts[3], 1, None]
        ]
    )

def test_leverage_ratio_too_high_failure(StratBoostedPoolDAIPrimary):
    leverage_ratio_too_high(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 60000e8)

def test_leverage_ratio_too_high(StratBoostedPoolDAIPrimary):
    balancer_share_too_high(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 60000e8)
