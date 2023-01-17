
import pytest
import brownie
from brownie import Wei, accounts, network, TradingModule
from brownie.network.state import Chain
from scripts.common import (
    DEX_ID, 
    TRADE_TYPE, 
    set_dex_flags, 
    set_trade_type_flags
)
from scripts.EnvironmentConfig import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def test_COMP_to_WETH_exact_in():
    env = getEnvironment(network.show_active())
    amount = Wei(200e18)
    env.tokens["COMP"].transfer(env.tradingModule, amount, {"from": env.whales["COMP"]})

    # To generate this trade data after advancing the block number
    # Call https://api.0x.org/swap/v1/quote?sellToken=0xc00e94cb662c3520282e6f5717214004a7f26888&buyToken=0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2&sellAmount=200000000000000000000&slippagePercentage=0.05
    tradeData = "0xd9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000ad78ebc5ac6200000000000000000000000000000000000000000000000000000481975fe675cac9800000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000c00e94cb662c3520282e6f5717214004a7f26888000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000a218a81e9163a1f29d"
    trade = [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        env.tokens["COMP"], 
        env.tokens["WETH"], 
        amount, 
        0, 
        chain.time(), 
        tradeData
    ]
    # Vault does not have permission to sell wstETH
    with brownie.reverts():
        env.tradingModule.executeTrade.call(DEX_ID["ZERO_EX"], trade, {"from": accounts[0]})

    # wstETH vault can't use 0x
    assert env.tradingModule.canExecuteTrade("0xF049B944eC83aBb50020774D48a8cf40790996e6", DEX_ID["ZERO_EX"], trade) == False

    # Give vault permission to sell wstETH
    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        env.tokens["COMP"].address, 
        [True, set_dex_flags(0, ZERO_EX=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    compBefore = env.tokens["COMP"].balanceOf(env.tradingModule)
    wethBefore = env.tokens["WETH"].balanceOf(env.tradingModule)
    ret = env.tradingModule.executeTrade(DEX_ID["ZERO_EX"], trade, {"from": accounts[0]})
    assert env.tokens["COMP"].balanceOf(env.tradingModule) == 0
    assert env.tokens["WETH"].balanceOf(env.tradingModule) >= 5408750927015628960
    assert ret.return_value[0] == compBefore - env.tokens["COMP"].balanceOf(env.tradingModule)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(env.tradingModule) - wethBefore
