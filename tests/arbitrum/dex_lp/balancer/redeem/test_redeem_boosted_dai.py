from brownie import accounts
from tests.fixtures import *
from scripts.common import get_dynamic_trade_params, get_redeem_params, get_univ3_single_data, DEX_ID, TRADE_TYPE
from tests.arbitrum.dex_lp.acceptance import (
    redeem,
    DAIPrimaryContext
)

def test_single_maturity_full_redemption_success(ArbStratAaveBoostedPoolDAIPrimary):
    redeemParams = get_redeem_params(0, 0)
    redeem(
        DAIPrimaryContext(*ArbStratAaveBoostedPoolDAIPrimary),
        [[10e18, 20e8, accounts[0], 0, redeemParams, [1.0]]]
    )