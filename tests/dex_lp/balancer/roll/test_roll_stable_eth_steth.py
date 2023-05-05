from brownie import accounts
from tests.fixtures import *
from tests.dex_lp.acceptance import roll, ETHPrimaryContext

def test_single_account_next_maturity_success(StratStableETHstETH):
    roll(ETHPrimaryContext(*StratStableETHstETH), 100e18, 150e8, accounts[0], 0, 1)
