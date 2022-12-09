from brownie import accounts
from brownie.convert import to_bytes
from tests.fixtures import *
from tests.balancer.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    balancer_share_too_high,
    ETHPrimaryContext
)
from tests.balancer.helpers import get_expected_borrow_amount
from scripts.common import (
    get_deposit_params, 
    get_deposit_trade_params,
    DEX_ID,
    TRADE_TYPE
)

def test_single_maturity_low_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [[100e18, 150e8, accounts[0], 0, None]]
    )

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [[20e18, 150e8, accounts[0], 0, None]]
    )

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [
            [100e18, 150e8, accounts[0], 0, None],
            [100e18, 150e8, accounts[1], 1, None]
        ]
    )

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [
            [20e18, 150e8, accounts[0], 0, None],
            [20e18, 150e8, accounts[1], 1, None]
        ]
    )

def test_multiple_accounts_in_each_maturity_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [
            [20e18, 150e8, accounts[0], 0, None],
            [20e18, 150e8, accounts[1], 0, None],
            [20e18, 150e8, accounts[2], 1, None],
            [20e18, 150e8, accounts[3], 1, None]
        ]
    )

def test_secondary_currency_trading_unwrapped_success(StratStableETHstETH):
    context = ETHPrimaryContext(*StratStableETHstETH)
    maturity = context.env.notional.getActiveMarkets(context.currencyId)[0][1]
    depositAmount = 20e18
    primaryBorrowAmount = 150e8
    expectedBorrowAmount = get_expected_borrow_amount(context.env, context.currencyId, maturity, primaryBorrowAmount)
    totalUnderlyingAmount = depositAmount + expectedBorrowAmount
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["CURVE"],  TRADE_TYPE["EXACT_IN_SINGLE"], (totalUnderlyingAmount) / 2, 5e6, True, bytes(0)
    ))
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [[depositAmount, primaryBorrowAmount, accounts[0], 0, depositParams]]
    )

def test_secondary_currency_trading_wrapped_success(StratStableETHstETH):
    context = ETHPrimaryContext(*StratStableETHstETH)
    maturity = context.env.notional.getActiveMarkets(context.currencyId)[0][1]
    depositAmount = 20e18
    primaryBorrowAmount = 150e8
    expectedBorrowAmount = get_expected_borrow_amount(context.env, context.currencyId, maturity, primaryBorrowAmount)
    totalUnderlyingAmount = depositAmount + expectedBorrowAmount
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["BALANCER_V2"],  TRADE_TYPE["EXACT_IN_SINGLE"], totalUnderlyingAmount / 2, 5e6, False, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32")]]
        )
    ))
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [[depositAmount, primaryBorrowAmount, accounts[0], 0, depositParams]]
    )

def test_leverage_ratio_too_high_failure(StratStableETHstETH):
    leverage_ratio_too_high(ETHPrimaryContext(*StratStableETHstETH), 5e18, 150e8)

def test_balancer_share_too_high(StratStableETHstETH):
    balancer_share_too_high(ETHPrimaryContext(*StratStableETHstETH), 5e18, 150e8)
