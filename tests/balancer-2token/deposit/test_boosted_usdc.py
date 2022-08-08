import pytest
import eth_abi
from brownie import Wei
from tests.fixtures import *
from scripts.common import get_deposit_params

def test_single_maturity_low_leverage_success(StratBoostedPoolUSDCPrimary):
    (env, vault, mock) = StratBoostedPoolUSDCPrimary
    maturity = env.notional.getActiveMarkets(3)[0][1]
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    env.notional.enterVault(
        env.whales["USDC"],
        vault.address,
        depositAmount,
        maturity,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": env.whales["USDC"]}
    )