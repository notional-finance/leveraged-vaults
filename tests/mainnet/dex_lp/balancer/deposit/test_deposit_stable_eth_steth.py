from brownie import accounts, ZERO_ADDRESS, interface
from brownie.convert import to_bytes
from brownie.network.state import Chain
from tests.fixtures import *
from tests.dex_lp.acceptance import (
    deposit, 
    leverage_ratio_too_high,
    pool_share_too_high,
    ETHPrimaryContext
)
from tests.dex_lp.helpers import get_expected_borrow_amount, get_deposit_op
from scripts.common import (
    get_deposit_params, 
    get_deposit_trade_params,
    set_dex_flags,
    set_trade_type_flags,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_low_leverage_success(StratStableETHstETH):
    deposit(ETHPrimaryContext(*StratStableETHstETH), [get_deposit_op(100e18, 150e8, accounts[0])])

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    deposit(ETHPrimaryContext(*StratStableETHstETH), [get_deposit_op(20e18, 150e8, accounts[0])])

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [get_deposit_op(100e18, 150e8, accounts[0]), get_deposit_op(100e18, 150e8, accounts[1], 1)]
    )

def test_multiple_maturities_high_leverage_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [get_deposit_op(20e18, 150e8, accounts[0]), get_deposit_op(20e18, 150e8, accounts[1], 1)]
    )

def test_multiple_accounts_in_each_maturity_success(StratStableETHstETH):
    deposit(
        ETHPrimaryContext(*StratStableETHstETH), 
        [
            get_deposit_op(20e18, 150e8, accounts[0]),
            get_deposit_op(20e18, 150e8, accounts[1]),
            get_deposit_op(20e18, 150e8, accounts[2], 1),
            get_deposit_op(20e18, 150e8, accounts[3], 1)
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
        DEX_ID["CURVE"],  TRADE_TYPE["EXACT_IN_SINGLE"], (totalUnderlyingAmount) / 2, 5e6, True, bytes()
    ))
    deposit(
        ETHPrimaryContext(*StratStableETHstETH),
        [get_deposit_op(depositAmount, primaryBorrowAmount, accounts[0], 0, depositParams, 0.5, depositTradeCurve)]
    )

def depositTradeCurve(env, vault, primaryAmountToSell):
    env.tradingModule.setTokenPermissions(
        env.tradingModule, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    trade = [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        ZERO_ADDRESS,
        env.tokens["stETH"].address, 
        primaryAmountToSell, 
        0, 
        chain.time() + 20000,
        bytes()
    ]
    env.tradingModule.executeTrade(DEX_ID["CURVE"], trade, {"from": env.whales["ETH"]})
    env.tokens["stETH"].approve(env.tokens["wstETH"].address, 2**256-1, {"from": env.tradingModule})
    interface.IWstETH(env.tokens["wstETH"].address).wrap(
        env.tokens["stETH"].balanceOf(env.tradingModule), {"from": env.tradingModule}
    )
    secondaryAmount = env.tokens["wstETH"].balanceOf(env.tradingModule)
    env.tokens["wstETH"].transfer(vault, secondaryAmount, {"from": env.tradingModule})
    return (secondaryAmount, 5)

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
        [get_deposit_op(depositAmount, primaryBorrowAmount, accounts[0], 0, depositParams, 0.5, depositTradeBalancer)]
    )

def depositTradeBalancer(env, vault, primaryAmountToSell):
    env.tradingModule.setTokenPermissions(
        env.tradingModule, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    trade = [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        ZERO_ADDRESS,
        env.tokens["wstETH"].address, 
        primaryAmountToSell, 
        0, 
        chain.time() + 20000, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32")]]
        )
    ]
    env.tradingModule.executeTrade(DEX_ID["BALANCER_V2"], trade, {"from": env.whales["ETH"]})
    secondaryAmount = env.tokens["wstETH"].balanceOf(env.tradingModule)
    env.tokens["wstETH"].transfer(vault, secondaryAmount, {"from": env.tradingModule})
    return (secondaryAmount, 3)

def test_leverage_ratio_too_high_failure(StratStableETHstETH):
    leverage_ratio_too_high(ETHPrimaryContext(*StratStableETHstETH), 5e18, 150e8)

def test_pool_share_too_high(StratStableETHstETH):
    pool_share_too_high(ETHPrimaryContext(*StratStableETHstETH), 5e18, 150e8)
