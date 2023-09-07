from brownie import accounts, ZERO_ADDRESS, interface, Wei
from brownie.convert import to_bytes
from brownie.network.state import Chain
from tests.fixtures import *
from tests.arbitrum.dex_lp.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    pool_share_too_high,
    wstETHPrimaryContext
)
from tests.arbitrum.dex_lp.helpers import get_expected_borrow_amount, get_deposit_op
from scripts.common import (
    get_deposit_params, 
    get_deposit_trade_params,
    set_dex_flags,
    set_trade_type_flags,
    DEX_ID,
    TRADE_TYPE
)

def test_single_maturity_low_leverage_success(ArbStratStablestETHETH):
    (env, vault, mock) = ArbStratStablestETHETH
    whale = accounts.at("0x9fb1750da6266a05601855bb62767ebc742707b1", force=True)
    env.tokens["wstETH"].approve(env.notional, 2**256-1, {"from": whale})
    env.notional.batchBalanceAction(whale, [[4, 5, Wei(9e18), 0, False, True]], {"from": whale })
    deposit(wstETHPrimaryContext(*ArbStratStablestETHETH), [get_deposit_op(1e18, 2e8, accounts[0], 0)])