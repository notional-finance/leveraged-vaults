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
        [[10000e18, 5000e8, accounts[0], 0]]
    )

def test_single_maturity_high_leverage_success(StratBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        [[10000e18, 40000e8, accounts[0], 0]]
    )

def test_leverage_ratio_too_high_failure(StratBoostedPoolDAIPrimary):
    leverage_ratio_too_high(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 60000e8)

def test_leverage_ratio_too_high(StratBoostedPoolDAIPrimary):
    balancer_share_too_high(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 60000e8)
