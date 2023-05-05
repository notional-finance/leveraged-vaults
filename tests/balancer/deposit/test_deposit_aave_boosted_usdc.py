from brownie import accounts
from tests.fixtures import *
from tests.balancer.acceptance import (
    USDCPrimaryContext, 
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high
)
from tests.balancer.helpers import (
    get_deposit_op
)

def test_single_maturity_low_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), [get_deposit_op(10000e6, 5000e8, accounts[0])])

def test_single_maturity_high_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), [get_deposit_op(10000e6, 40000e8, accounts[0])])

def test_multiple_maturities_low_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit(
        USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 
        [get_deposit_op(10000e6, 5000e8, accounts[0]), get_deposit_op(10000e6, 5000e8, accounts[1], 1)]
    )

def test_multiple_maturities_high_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit(
        USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 
        [get_deposit_op(10000e6, 40000e8, accounts[0]), get_deposit_op(10000e6, 40000e8, accounts[1], 1)]
    )

def test_multiple_accounts_in_each_maturity_success(StratBoostedPoolUSDCPrimary):
    deposit(
        USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 
        [
            get_deposit_op(10000e6, 40000e8, accounts[0]),
            get_deposit_op(10000e6, 40000e8, accounts[1]),
            get_deposit_op(10000e6, 40000e8, accounts[2], 1),
            get_deposit_op(10000e6, 40000e8, accounts[3], 1)
        ]
    )

def test_leverage_ratio_too_high_failure(StratBoostedPoolUSDCPrimary):
    leverage_ratio_too_high(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 200000e8)

def test_balancer_share_too_high(StratBoostedPoolUSDCPrimary):
    balancer_share_too_high(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 60000e8)
