from brownie import accounts, Wei
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.arbitrum.dex_lp.acceptance import (
    redeem,
    ETHPrimaryContext
)
from scripts.common import get_dynamic_trade_params, get_redeem_params, DEX_ID, TRADE_TYPE

def test_single_maturity_full_redemption_unwrapped_success(ArbStratStableETHstETH):
    (env, vault, mock) = ArbStratStableETHstETH
    whale = accounts.at("0xc948eb5205bde3e18cac4969d6ad3a56ba7b2347", force=True)
    env.notional.batchBalanceAction(whale, [[4, 1, Wei(9e18), 0, False, True]], {"from": whale, "value": Wei(9e18)})
    redeem(
        ETHPrimaryContext(*ArbStratStableETHstETH),
        [[1e18, 2e8, accounts[0], 0, get_redeem_params(0, 0), [1.0]]]
    )

# TODO: test no 0x trading