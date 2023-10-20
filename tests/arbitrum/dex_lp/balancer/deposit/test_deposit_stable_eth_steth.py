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

chain = Chain()

def test_single_maturity_low_leverage_success(ArbStratStableETHstETH):
    (env, vault, mock) = ArbStratStableETHstETH
    deposit(ETHPrimaryContext(*ArbStratStableETHstETH), [get_deposit_op(0.1e18, 0.2e8, accounts[0], 0)])

@pytest.mark.skip
def test_secondary_currency_trading_wrapped_success(ArbStratStableETHstETH):
    (env, vault, mock) = ArbStratStableETHstETH
    whale = accounts.at("0xc948eb5205bde3e18cac4969d6ad3a56ba7b2347", force=True)
    env.notional.batchBalanceAction(whale, [[4, 1, Wei(9e18), 0, False, True]], {"from": whale, "value": Wei(9e18)})
    context = ETHPrimaryContext(*ArbStratStableETHstETH)
    maturity = context.env.notional.getActiveMarkets(context.currencyId)[0][1]
    depositAmount = 1e18
    primaryBorrowAmount = 2e8
    expectedBorrowAmount = get_expected_borrow_amount(context.env, context.currencyId, maturity, primaryBorrowAmount)
    totalUnderlyingAmount = depositAmount + expectedBorrowAmount
    depositParams = get_deposit_params(trade=get_deposit_trade_params(
        DEX_ID["BALANCER_V2"],  TRADE_TYPE["EXACT_IN_SINGLE"], totalUnderlyingAmount / 2, 5e6, False, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x36bf227d6bac96e2ab1ebb5492ecec69c691943f000200000000000000000316", "bytes32")]]
        )
    ))
    deposit(
        ETHPrimaryContext(*ArbStratStableETHstETH), 
        [get_deposit_op(depositAmount, primaryBorrowAmount, accounts[0], 0, depositParams, 0.5, depositTradeBalancer)]
    )

def depositTradeBalancer(env, vault, primaryAmountToSell):
    env.tradingModule.setTokenPermissions(
        env.tradingModule, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.tradingModuleOwner})
    trade = [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        ZERO_ADDRESS,
        env.tokens["wstETH"].address, 
        primaryAmountToSell, 
        0, 
        chain.time() + 20000, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x36bf227d6bac96e2ab1ebb5492ecec69c691943f000200000000000000000316", "bytes32")]]
        )
    ]
    env.tradingModule.executeTrade(DEX_ID["BALANCER_V2"], trade, {"from": env.whales["ETH"]})
    secondaryAmount = env.tokens["wstETH"].balanceOf(env.tradingModule)
    env.tokens["wstETH"].transfer(vault, secondaryAmount, {"from": env.tradingModule})
    return (secondaryAmount, 3)
