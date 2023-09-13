from brownie import accounts
from tests.fixtures import *
from tests.dex_lp.acceptance import (
    redeem,
    ETHPrimaryContext
)
from scripts.common import get_redeem_params

def test_single_maturity_full_redemption_unwrapped_success(StratCurveStableETHstETH):
    redeemParams = get_redeem_params(0, 0)
    redeem(
        ETHPrimaryContext(*StratCurveStableETHstETH),
        [[100e18, 150e8, accounts[0], 0, redeemParams, [1.0]]]
    )
    
def test_single_maturity_partial_redemption_success(StratCurveStableETHstETH):
    redeemParams = get_redeem_params(0, 0)
    redeem(
        ETHPrimaryContext(*StratCurveStableETHstETH),
        [[100e18, 300e8, accounts[0], 0, redeemParams, [0.5, 1.0]]]
    )

def test_multiple_maturities_full_redemption_success(StratCurveStableETHstETH):
    redeemParams = get_redeem_params(0, 0)
    redeem(
        ETHPrimaryContext(*StratCurveStableETHstETH),
        [
            [100e18, 150e8, accounts[0], 0, redeemParams, [1.0]],
            [100e18, 150e8, accounts[1], 1, redeemParams, [1.0]]
        ]
    )

def test_multiple_maturities_partial_redemption_success(StratCurveStableETHstETH):
    redeemParams = get_redeem_params(0, 0)
    redeem(
        ETHPrimaryContext(*StratCurveStableETHstETH),
        [
            [100e18, 300e8, accounts[0], 0, redeemParams, [0.5, 1.0]],
            [100e18, 300e8, accounts[1], 1, redeemParams, [0.5, 1.0]]
        ]
    )
