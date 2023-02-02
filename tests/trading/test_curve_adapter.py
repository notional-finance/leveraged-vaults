
import pytest
import brownie
from brownie import Wei, accounts, network, interface, MockVault
from brownie.network.state import Chain
from scripts.common import DEX_ID, TRADE_TYPE, set_dex_flags, set_trade_type_flags, get_crv_batch_data
from scripts.EnvironmentConfig import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def curve_trade_exact_in_single(sellToken, buyToken, amount, limit):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_SINGLE"], sellToken, buyToken, amount, limit, deadline, bytes()
    ]

def curve_trade_exact_in_batch(sellToken, buyToken, amount):
    deadline = chain.time() + 20000
    router = interface.ICurveRouter("0xfA9a30350048B2BF66865ee20363067c66f67e58")
    routes = router.get_exchange_routing(sellToken, buyToken, amount)
    return [
        TRADE_TYPE["EXACT_IN_BATCH"], 
        sellToken, 
        buyToken, 
        amount, 
        0, 
        deadline,
        get_crv_batch_data(sellToken, buyToken, amount)
    ]

def test_stETH_to_weth_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["stETH"].transfer(mockVault, 1e18, {"from": env.whales["stETH"]})

    trade = curve_trade_exact_in_single(
        env.tokens["stETH"].address, env.tokens["WETH"].address, env.tokens["stETH"].balanceOf(mockVault), 0
    )

    # Vault does not have permission to sell stETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell stETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["stETH"].address, 
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    stETHBefore = env.tokens["stETH"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["stETH"].balanceOf(mockVault) == 1 # why???
    assert ret.return_value[0] == stETHBefore - env.tokens["stETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore

def test_weth_to_stETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["WETH"].transfer(mockVault, 1e18, {"from": env.whales["WETH"]})

    trade = curve_trade_exact_in_single(
        env.tokens["WETH"].address, env.tokens["stETH"].address, env.tokens["WETH"].balanceOf(mockVault), 0
    )

    # Vault does not have permission to sell WETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell WETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["WETH"].address, 
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    stETHBefore = env.tokens["stETH"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["WETH"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == wethBefore - env.tokens["WETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["stETH"].balanceOf(mockVault) - stETHBefore

def test_stETH_to_ETH_to_DAI_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["stETH"].transfer(mockVault, 1e18, {"from": env.whales["stETH"]})

    trade = curve_trade_exact_in_batch(
        env.tokens["stETH"].address, env.tokens["DAI"].address, env.tokens["stETH"].balanceOf(mockVault)
    )

    # Vault does not have permission to sell stETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell stETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["stETH"].address, 
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    stETHBefore = env.tokens["stETH"].balanceOf(mockVault)
    daiBefore = env.tokens["DAI"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["stETH"].balanceOf(mockVault) == 1
    assert ret.return_value[0] == stETHBefore - env.tokens["stETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["DAI"].balanceOf(mockVault) - daiBefore

def test_stETH_to_weth_exact_in_static_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["stETH"].transfer(mockVault, 1e18, {"from": env.whales["stETH"]})

    trade = curve_trade_exact_in_single(
        env.tokens["stETH"].address, 
        env.tokens["WETH"].address, 
        env.tokens["stETH"].balanceOf(mockVault), 
        Wei(0.95e18)
    )

    # Vault does not have permission to sell stETH
    with brownie.reverts():
        mockVault.executeTrade.call(DEX_ID["CURVE"], trade, {"from": accounts[0]})

    # Give vault permission to sell stETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["stETH"].address, 
        [True, set_dex_flags(0, CURVE=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    # Slippage too high
    with brownie.reverts():
        badTrade = curve_trade_exact_in_single(
            env.tokens["stETH"].address, 
            env.tokens["WETH"].address, 
            env.tokens["stETH"].balanceOf(mockVault), 
            5e18
        )
        mockVault.executeTrade.call(DEX_ID["CURVE"], badTrade, {"from": accounts[0]})

    stETHBefore = env.tokens["stETH"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTrade(DEX_ID["CURVE"], trade, {"from": accounts[0]})
    assert env.tokens["stETH"].balanceOf(mockVault) == 1 # why???
    assert ret.return_value[0] == stETHBefore - env.tokens["stETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore
