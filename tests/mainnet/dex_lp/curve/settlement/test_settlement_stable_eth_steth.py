from brownie import accounts
from tests.fixtures import *
from tests.dex_lp.acceptance import (
    ETHPrimaryContext, 
    normal_settlement,
    post_maturity_settlement,
    emergency_settlement
)

def test_normal_single_maturity(StratCurveStableETHstETH):
    redeemParams = [0, 0, None]
    normal_settlement(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        100e18, 
        300e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.5
    )

def test_post_maturity_single_maturity(StratCurveStableETHstETH):
    redeemParams = [0, 0, None]
    post_maturity_settlement(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        100e18, 
        300e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.5
    )

def test_emergency_single_maturity(StratCurveStableETHstETH):
    redeemParams = [0, 0, None]
    emergency_settlement(
        ETHPrimaryContext(*StratCurveStableETHstETH), 
        100e18, 
        300e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams
    )
