
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from scripts.common import get_two_token_redeem_params
from tests.balancer.helpers import enterMaturity, exitVaultPercent
from tests.balancer.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high,
    ETHPrimaryContext
)

chain = Chain()

def test_single_maturity_low_leverage_success(StratCurveStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        [[100e18, 150e8, accounts[0], 0, None]]
    )
