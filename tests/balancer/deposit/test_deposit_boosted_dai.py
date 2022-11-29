from tests.fixtures import *
from tests.balancer.acceptance import (
    DAIPrimaryContext, 
    deposit_test, 
    negative_test_leverage_ratio_too_high
)

def test_single_maturity_low_leverage_success(StratBoostedPoolDAIPrimary):
    deposit_test(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 5000e8)

def test_single_maturity_high_leverage_success(StratBoostedPoolDAIPrimary):
    deposit_test(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 40000e8)

def test_leverage_ratio_too_high_failure(StratBoostedPoolDAIPrimary):
    negative_test_leverage_ratio_too_high(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 60000e8)
