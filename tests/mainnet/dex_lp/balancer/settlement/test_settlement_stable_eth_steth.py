from brownie import accounts, Wei
from tests.fixtures import *
from tests.dex_lp.acceptance import (
    ETHPrimaryContext, 
    normal_settlement,
    post_maturity_settlement,
    emergency_settlement
)
from scripts.common import DEX_ID, TRADE_TYPE

def test_normal_single_maturity(StratStableETHstETH):
    redeemParams = [0, 0, [DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(3e6), True, bytes()]]
    normal_settlement(
        ETHPrimaryContext(*StratStableETHstETH), 
        100e18, 
        300e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.5
    )

def test_post_maturity_single_maturity(StratStableETHstETH):
    redeemParams = [0, 0, [DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(5e6), True, bytes()]]
    post_maturity_settlement(
        ETHPrimaryContext(*StratStableETHstETH), 
        100e18, 
        300e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.5
    )

def test_emergency_single_maturity(StratStableETHstETH):
    redeemParams = [0, 0, [DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(4e6), True, bytes()]]
    emergency_settlement(
        ETHPrimaryContext(*StratStableETHstETH), 
        100e18, 
        300e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams
    )
