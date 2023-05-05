from brownie import accounts
from tests.fixtures import *
from tests.balancer.acceptance import (
    DAIPrimaryContext, 
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high
)
from tests.balancer.helpers import get_deposit_op

def test_single_maturity_low_leverage_success(StratEulerBoostedPoolDAIPrimary):
    deposit(DAIPrimaryContext(*StratEulerBoostedPoolDAIPrimary), [get_deposit_op(10000e18, 5000e8, accounts[0], 0)])

def test_single_maturity_high_leverage_success(StratEulerBoostedPoolDAIPrimary):
    deposit(DAIPrimaryContext(*StratEulerBoostedPoolDAIPrimary), [get_deposit_op(10000e18, 40000e8, accounts[0], 0)])

def test_multiple_maturities_low_leverage_success(StratEulerBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratEulerBoostedPoolDAIPrimary), 
        [get_deposit_op(10000e18, 5000e8, accounts[0]), get_deposit_op(10000e18, 5000e8, accounts[1], 1)]
    )

def test_multiple_maturities_high_leverage_success(StratEulerBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratEulerBoostedPoolDAIPrimary), 
        [
            get_deposit_op(10000e18, 40000e8, accounts[0]),
            get_deposit_op(10000e18, 40000e8, accounts[1], 1)
        ]
    )

def test_multiple_accounts_in_each_maturity_success(StratEulerBoostedPoolDAIPrimary):
    deposit(
        DAIPrimaryContext(*StratEulerBoostedPoolDAIPrimary), 
        [
            get_deposit_op(10000e18, 40000e8, accounts[0]),
            get_deposit_op(10000e18, 40000e8, accounts[1]),
            get_deposit_op(10000e18, 40000e8, accounts[2], 1),
            get_deposit_op(10000e18, 40000e8, accounts[3], 1)
        ]
    )

def test_leverage_ratio_too_high_failure(StratEulerBoostedPoolDAIPrimary):
    leverage_ratio_too_high(DAIPrimaryContext(*StratEulerBoostedPoolDAIPrimary), 10000e18, 200000e8)

def test_leverage_ratio_too_high(StratEulerBoostedPoolDAIPrimary):
    balancer_share_too_high(DAIPrimaryContext(*StratEulerBoostedPoolDAIPrimary), 10000e18, 60000e8)
