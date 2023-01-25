
import pytest
import brownie
from brownie import Wei, accounts, network
from brownie.network.state import Chain
from scripts.common import (
    DEX_ID, 
    TRADE_TYPE, 
    set_dex_flags, 
    set_trade_type_flags
)
from scripts.EnvironmentConfig import getEnvironment
from tests.zeroex.helpers import load_test_data, save_test_data, fetch_0x_data

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def test_COMP_to_WETH_exact_in(request):
    env = getEnvironment(network.show_active())
    amount = Wei(200e18)
    env.tokens["COMP"].transfer(env.tradingModule, amount, {"from": env.whales["COMP"]})

    testData = load_test_data(request.node.name)
    if env.forkBlockNumber > testData["blockNumber"]:
        tradeData = fetch_0x_data(
            env.tokens["COMP"],
            env.tokens["WETH"],
            amount,
            0.3
        )
        save_test_data(request.node.name, env.forkBlockNumber, [tradeData])
    else:
        tradeData = testData["params"][0]

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
