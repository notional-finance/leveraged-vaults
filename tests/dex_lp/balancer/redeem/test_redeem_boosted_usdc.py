from brownie import accounts
from tests.fixtures import *
from scripts.common import get_dynamic_trade_params, get_redeem_params, get_univ3_single_data, DEX_ID, TRADE_TYPE
from tests.dex_lp.acceptance import (
    redeem,
    USDCPrimaryContext
)

def test_single_maturity_full_redemption_success(StratAaveBoostedPoolUSDCPrimary):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    redeem(
        USDCPrimaryContext(*StratAaveBoostedPoolUSDCPrimary),
        [[10000e6, 5000e8, accounts[0], 0, redeemParams, [1.0]]]
    )

def test_single_maturity_partial_redemption_success(StratAaveBoostedPoolUSDCPrimary):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    redeem(
        USDCPrimaryContext(*StratAaveBoostedPoolUSDCPrimary),
        [[10000e6, 5000e8, accounts[0], 0, redeemParams, [0.5]]]
    )

def test_multiple_maturities_full_redemption_success(StratAaveBoostedPoolUSDCPrimary):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    redeem(
        USDCPrimaryContext(*StratAaveBoostedPoolUSDCPrimary),
        [
            [10000e6, 5000e8, accounts[0], 0, redeemParams, [1.0]],
            [10000e6, 5000e8, accounts[1], 1, redeemParams, [1.0]]
        ]
    )

def test_multiple_maturities_partial_redemption_success(StratBoostedPoolUSDCPrimary):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    redeem(
        USDCPrimaryContext(*StratBoostedPoolUSDCPrimary),
        [
            [10000e6, 5000e8, accounts[0], 0, redeemParams, [0.5, 1.0]],
            [10000e6, 5000e8, accounts[1], 1, redeemParams, [0.5, 1.0]]
        ]
    )