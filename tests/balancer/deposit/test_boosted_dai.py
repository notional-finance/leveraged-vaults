import pytest
import eth_abi
from brownie import Wei
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
    pass
