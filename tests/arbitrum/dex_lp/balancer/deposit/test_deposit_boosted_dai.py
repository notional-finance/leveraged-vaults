from brownie import accounts
from tests.fixtures import *
from tests.arbitrum.dex_lp.acceptance import (
    DAIPrimaryContext, 
    deposit, 
    leverage_ratio_too_high,
    pool_share_too_high
)
from tests.arbitrum.dex_lp.helpers import get_deposit_op

def test_single_maturity_low_leverage_success(ArbStratAaveBoostedPoolDAIPrimary):
    deposit(DAIPrimaryContext(*ArbStratAaveBoostedPoolDAIPrimary), [get_deposit_op(10e18, 20e8, accounts[0], 0)])
