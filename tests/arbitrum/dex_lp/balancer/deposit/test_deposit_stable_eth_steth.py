from brownie import accounts, ZERO_ADDRESS, interface, Wei
from brownie.convert import to_bytes
from brownie.network.state import Chain
from tests.fixtures import *
from tests.arbitrum.dex_lp.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    pool_share_too_high,
    ETHPrimaryContext
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

def test_single_maturity_low_leverage_success(ArbStratStableETHstETH):
    (env, vault, mock) = ArbStratStableETHstETH
    whale = accounts.at("0xc948eb5205bde3e18cac4969d6ad3a56ba7b2347", force=True)
    env.notional.batchBalanceAction(whale, [[4, 1, Wei(9e18), 0, False, True]], {"from": whale, "value": Wei(9e18)})
    deposit(ETHPrimaryContext(*ArbStratStableETHstETH), [get_deposit_op(1e18, 2e8, accounts[0], 0)])
