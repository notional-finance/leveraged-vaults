from brownie import accounts
from tests.fixtures import *
from tests.dex_lp.acceptance import roll, USDCPrimaryContext

def test_single_account_next_maturity_success(StratBoostedPoolUSDCPrimary):
    roll(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 5000e8, accounts[0], 0, 1)
