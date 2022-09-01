import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import (
    get_deposit_params, 
    get_dynamic_trade_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_account_next_maturity_success(StratBoostedPoolUSDCPrimary):
    (env, vault, mock) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity1 = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    maturity2 = env.notional.getActiveMarkets(2)[1][1]
    env.notional.rollVaultPosition(
        env.whales["USDC"],
        vault.address,
        primaryBorrowAmount * 1.1,
        maturity2,
        0,
        0,
        get_deposit_params(),
        {"from": env.whales["USDC"]}
    )