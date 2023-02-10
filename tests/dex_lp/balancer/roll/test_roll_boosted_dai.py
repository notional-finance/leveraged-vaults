from brownie import accounts
from tests.fixtures import *
from tests.dex_lp.acceptance import roll, DAIPrimaryContext

def test_single_account_next_maturity_success(StratBoostedPoolDAIPrimary):
    roll(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 5000e8, accounts[0], 0, 1)
