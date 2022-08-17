import pytest
import eth_abi
from brownie import Wei
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import get_deposit_params

def test_single_maturity_low_leverage_success(StratBoostedPoolUSDCPrimary):
    (env, vault, mock) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
