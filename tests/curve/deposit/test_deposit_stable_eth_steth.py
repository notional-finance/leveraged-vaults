
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from scripts.common import get_two_token_redeem_params
from tests.balancer.helpers import enterMaturity, exitVaultPercent

chain = Chain()

def test_single_maturity_low_leverage_success(StratCurveStableETHstETH):
    (env, vault) = StratCurveStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    enterMaturity(env, vault, 1, maturity, 1e18, 3e8, accounts[0])
    chain.mine(10)
    #exitVaultPercent(env, vault, accounts[0], 1.0, get_two_token_redeem_params(3.8e18, 0, True, bytes(0)))
    assert 1 == 2
