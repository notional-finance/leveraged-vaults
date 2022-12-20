
import pytest
import brownie
from brownie import ZERO_ADDRESS, accounts, network, MockVault
from brownie.network.state import Chain
from scripts.common import (
    DEX_ID, 
    TRADE_TYPE, 
    get_univ3_batch_data, 
    get_univ3_single_data, 
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

def univ3_trade_exact_in_single(sellToken, buyToken, amount, limit, fee):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_SINGLE"], sellToken, buyToken, amount, limit, deadline, get_univ3_single_data(fee)
    ]

def univ3_trade_exact_in_batch(sellToken, buyToken, amount, path):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_BATCH"], sellToken, buyToken, amount, 0, deadline, get_univ3_batch_data(path)
    ]

def test_USDC_to_WETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["USDC"].transfer(mockVault, 100e6, {"from": env.whales["USDC"]})

    trade = univ3_trade_exact_in_single(
        env.tokens["USDC"].address, env.tokens["WETH"].address, env.tokens["USDC"].balanceOf(mockVault), 0, 3000
    )

    # Vault does not have permission to sell USDC
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell USDC
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["USDC"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == usdcBefore - env.tokens["USDC"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore

def test_USDC_to_ETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["USDC"].transfer(mockVault, 100e6, {"from": env.whales["USDC"]})

    trade = univ3_trade_exact_in_single(
        env.tokens["USDC"].address, ZERO_ADDRESS, env.tokens["USDC"].balanceOf(mockVault), 0, 3000
    )

    # Vault does not have permission to sell USDC
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell USDC
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["USDC"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == usdcBefore - env.tokens["USDC"].balanceOf(mockVault)
    assert ret.return_value[1] == mockVault.balance() - ethBefore

def test_USDC_to_WETH_to_DAI_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["USDC"].transfer(mockVault, 100e6, {"from": env.whales["USDC"]})

    trade = univ3_trade_exact_in_batch(
        env.tokens["USDC"].address, 
        env.tokens["DAI"].address, 
        env.tokens["USDC"].balanceOf(mockVault),
        [env.tokens["USDC"].address, 3000, env.tokens["WETH"].address, 3000, env.tokens["DAI"].address]
    )

    # Vault does not have permission to sell USDC
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell USDC
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    daiBefore = env.tokens["DAI"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["USDC"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == usdcBefore - env.tokens["USDC"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["DAI"].balanceOf(mockVault) - daiBefore

def test_WETH_to_USDC_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["WETH"].transfer(mockVault, 1e18, {"from": env.whales["WETH"]})

    trade = univ3_trade_exact_in_single(
        env.tokens["WETH"].address, env.tokens["USDC"].address, env.tokens["WETH"].balanceOf(mockVault), 0, 3000
    )

    # Vault does not have permission to sell WETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell WETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["WETH"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["WETH"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == wethBefore - env.tokens["WETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["USDC"].balanceOf(mockVault) - usdcBefore

def test_ETH_to_USDC_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.whales["ETH_EOA"].transfer(mockVault, 1e18)

    trade = univ3_trade_exact_in_single(
        ZERO_ADDRESS, env.tokens["USDC"].address, mockVault.balance(), 0, 3000
    )

    # Vault does not have permission to sell ETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell ETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})
    assert mockVault.balance() == 0
    assert ret.return_value[0] == ethBefore - mockVault.balance()
    assert ret.return_value[1] == env.tokens["USDC"].balanceOf(mockVault) - usdcBefore

def test_ETH_to_USDC_to_DAI_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.whales["ETH_EOA"].transfer(mockVault, 1e18)

    tradePath = [env.tokens["WETH"].address, 3000, env.tokens["USDC"].address, 100, env.tokens["DAI"].address]
    trade = univ3_trade_exact_in_batch(ZERO_ADDRESS, env.tokens["DAI"].address, mockVault.balance(), tradePath)

    # Vault does not have permission to sell ETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell ETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    # Bad path should revert
    with brownie.reverts():
        badPath = [env.tokens["WETH"].address, 3000, env.tokens["USDC"].address, 3000, env.tokens["USDT"].address]
        badTrade = univ3_trade_exact_in_batch(ZERO_ADDRESS, env.tokens["DAI"].address, mockVault.balance(), badPath)
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], badTrade, 5e6, {"from": accounts[0]})

    daiBefore = env.tokens["DAI"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})
    assert mockVault.balance() == 0
    assert ret.return_value[0] == ethBefore - mockVault.balance()
    assert ret.return_value[1] == env.tokens["DAI"].balanceOf(mockVault) - daiBefore

def test_USDC_to_WETH_exact_in_static_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["USDC"].transfer(mockVault, 2000e6, {"from": env.whales["USDC"]})

    trade = univ3_trade_exact_in_single(
        env.tokens["USDC"].address, 
        env.tokens["WETH"].address, 
        env.tokens["USDC"].balanceOf(mockVault), 
        1e18, 
        3000
    )

    # Vault does not have permission to sell USDC
    with brownie.reverts():
        mockVault.executeTrade.call(DEX_ID["UNISWAP_V3"], trade, {"from": accounts[0]})

    # Give vault permission to sell USDC
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, UNISWAP_V3=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    with brownie.reverts():
        badTrade = univ3_trade_exact_in_single(
            env.tokens["USDC"].address, 
            env.tokens["WETH"].address, 
            env.tokens["USDC"].balanceOf(mockVault), 
            5e18, 
            3000
        )
        mockVault.executeTrade.call(DEX_ID["UNISWAP_V3"], badTrade, {"from": accounts[0]})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTrade(DEX_ID["UNISWAP_V3"], trade, {"from": accounts[0]})
    assert env.tokens["USDC"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == usdcBefore - env.tokens["USDC"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore
