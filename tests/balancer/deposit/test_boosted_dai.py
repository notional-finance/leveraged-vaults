import pytest
import brownie
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import get_deposit_params

def test_single_maturity_low_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])

def test_single_maturity_high_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 40000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])

def test_leverage_ratio_too_high_failure(StratBoostedPoolDAIPrimary):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 60000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"], True)
