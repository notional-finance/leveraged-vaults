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

def test_single_account_next_maturity_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    maturity2 = env.notional.getActiveMarkets(1)[1][1]
    env.notional.rollVaultPosition(
        accounts[0],
        vault.address,
        primaryBorrowAmount * 1.1,
        maturity2,
        0,
        0,
        get_deposit_params(),
        {"from": accounts[0]}
    )