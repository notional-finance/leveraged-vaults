from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import snapshot_invariants, check_invariants, enterMaturity
from scripts.common import (get_deposit_params)

chain = Chain()

def test_single_account_next_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 100e18
    maturity1 = env.notional.getActiveMarkets(currencyId)[0][1]
    maturity2 = env.notional.getActiveMarkets(currencyId)[1][1]
    snapshot = snapshot_invariants(env, vault, [maturity1, maturity2])
    enterMaturity(env, vault, currencyId, maturity1, depositAmount, primaryBorrowAmount, accounts[0])
    env.notional.rollVaultPosition(
        accounts[0],
        vault.address,
        primaryBorrowAmount * 1.1,
        maturity2,
        0,
        0,
        0,
        get_deposit_params(),
        {"from": accounts[0]}
    )
    check_invariants(env, vault, [accounts[0]], [maturity1, maturity2], snapshot)
