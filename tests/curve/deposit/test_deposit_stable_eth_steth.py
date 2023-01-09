
from brownie import accounts
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity

def test_single_maturity_low_leverage_success(StratCurveStableETHstETH):
    (env, vault) = StratCurveStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    enterMaturity(env, vault, 1, maturity, 1e18, 3e8, accounts[0])
    assert 1 == 2
