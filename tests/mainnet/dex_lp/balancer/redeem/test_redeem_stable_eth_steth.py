from brownie import accounts
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.dex_lp.acceptance import (
    redeem,
    ETHPrimaryContext
)
from scripts.common import get_dynamic_trade_params, get_redeem_params, DEX_ID, TRADE_TYPE

def test_single_maturity_full_redemption_unwrapped_success(StratStableETHstETH):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes()
    ))
    redeem(
        ETHPrimaryContext(*StratStableETHstETH),
        [[100e18, 150e8, accounts[0], 0, redeemParams, [1.0]]]
    )

def test_single_maturity_full_redemption_wrapped_success(StratStableETHstETH):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["BALANCER_V2"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, False,
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32")]]
        )
    ))
    redeem(
        ETHPrimaryContext(*StratStableETHstETH),
        [[100e18, 150e8, accounts[0], 0, redeemParams, [1.0]]]
    )
    
def test_single_maturity_partial_redemption_success(StratStableETHstETH):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes()
    ))
    redeem(
        ETHPrimaryContext(*StratStableETHstETH),
        [[100e18, 300e8, accounts[0], 0, redeemParams, [0.5, 1.0]]]
    )

def test_multiple_maturities_full_redemption_success(StratStableETHstETH):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes()
    ))
    redeem(
        ETHPrimaryContext(*StratStableETHstETH),
        [
            [100e18, 150e8, accounts[0], 0, redeemParams, [1.0]],
            [100e18, 150e8, accounts[1], 1, redeemParams, [1.0]]
        ]
    )

def test_multiple_maturities_partial_redemption_success(StratStableETHstETH):
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes()
    ))
    redeem(
        ETHPrimaryContext(*StratStableETHstETH),
        [
            [100e18, 300e8, accounts[0], 0, redeemParams, [0.5, 1.0]],
            [100e18, 300e8, accounts[1], 1, redeemParams, [0.5, 1.0]]
        ]
    )
