import pytest
import brownie
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import get_deposit_params

def test_single_maturity_low_leverage_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])

def test_single_maturity_high_leverage_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 40000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])

def test_leverage_ratio_too_high_failure(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 60000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"], True)
