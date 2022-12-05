from brownie import accounts
from tests.fixtures import *
from tests.balancer.acceptance import (
    USDCPrimaryContext, 
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high
)

def test_single_maturity_low_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit(
        USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 
        [[10000e6, 5000e8, accounts[0], 0]]
    )

def test_single_maturity_high_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit(
        USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 
        [[10000e6, 40000e8, accounts[0], 0]]
    )

def test_leverage_ratio_too_high_failure(StratBoostedPoolUSDCPrimary):
    leverage_ratio_too_high(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 60000e8)

def test_balancer_share_too_high(StratBoostedPoolUSDCPrimary):
    balancer_share_too_high(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 60000e8)
