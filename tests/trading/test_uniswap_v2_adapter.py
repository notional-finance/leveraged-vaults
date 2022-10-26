
import pytest
import brownie
from brownie import Wei, ZERO_ADDRESS, accounts, network, MockVault
from brownie.network.state import Chain
from scripts.common import DEX_ID, TRADE_TYPE, get_univ2_data, set_dex_flags, set_trade_type_flags
from scripts.EnvironmentConfig import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def univ2_trade_exact_in_single(env, sellToken, buyToken, amount, limit):
    deadline = chain.time() + 200000
    pathSellToken = sellToken
    if pathSellToken == ZERO_ADDRESS:
        pathSellToken = env.tokens["WETH"].address
    pathBuyToken = buyToken
    if pathBuyToken == ZERO_ADDRESS:
        pathBuyToken = env.tokens["WETH"].address
    return [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        sellToken, 
        buyToken, 
        amount, 
        limit, 
        deadline, 
        get_univ2_data([pathSellToken, pathBuyToken])
    ]

def test_USDC_to_WETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["USDC"].transfer(mockVault, 100e6, {"from": env.whales["USDC"]})

    trade = univ2_trade_exact_in_single(
        env, env.tokens["USDC"].address, env.tokens["WETH"].address, env.tokens["USDC"].balanceOf(mockVault), 0
    )

    # Vault does not have permission to sell USDC
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell USDC
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, UNISWAP_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["USDC"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == usdcBefore - env.tokens["USDC"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore

def test_USDC_to_ETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["USDC"].transfer(mockVault, 100e6, {"from": env.whales["USDC"]})

    trade = univ2_trade_exact_in_single(
        env, env.tokens["USDC"].address, ZERO_ADDRESS, env.tokens["USDC"].balanceOf(mockVault), 0
    )

    # Vault does not have permission to sell USDC
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell USDC
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, UNISWAP_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["USDC"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == usdcBefore - env.tokens["USDC"].balanceOf(mockVault)
    assert ret.return_value[1] == mockVault.balance() - ethBefore

def test_DAI_to_WETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["DAI"].transfer(mockVault, 100e18, {"from": env.whales["DAI_EOA"]})

    trade = univ2_trade_exact_in_single(
        env, env.tokens["DAI"].address, env.tokens["WETH"].address, env.tokens["DAI"].balanceOf(mockVault), 0
    )

    # Vault does not have permission to sell DAI
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell DAI
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["DAI"].address, 
        [True, set_dex_flags(0, UNISWAP_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    daiBefore = env.tokens["DAI"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["DAI"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == daiBefore - env.tokens["DAI"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore

def test_WETH_to_USDC_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["WETH"].transfer(mockVault, 1e18, {"from": env.whales["WETH"]})

    trade = univ2_trade_exact_in_single(
        env, env.tokens["WETH"].address, env.tokens["USDC"].address, env.tokens["WETH"].balanceOf(mockVault), 0
    )

    # Vault does not have permission to sell WETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell WETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["WETH"].address, 
        [True, set_dex_flags(0, UNISWAP_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})
    assert env.tokens["WETH"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == wethBefore - env.tokens["WETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["USDC"].balanceOf(mockVault) - usdcBefore

def test_ETH_to_USDC_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.whales["ETH_EOA"].transfer(mockVault, 1e18)

    trade = univ2_trade_exact_in_single(
        env, ZERO_ADDRESS, env.tokens["USDC"].address, mockVault.balance(), 0
    )

    # Vault does not have permission to sell ETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell ETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        ZERO_ADDRESS, 
        [True, set_dex_flags(0, UNISWAP_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["UNISWAP_V2"], trade, 5e6, {"from": accounts[0]})
    assert mockVault.balance() == 0
    assert ret.return_value[0] == ethBefore - mockVault.balance()
    assert ret.return_value[1] == env.tokens["USDC"].balanceOf(mockVault) - usdcBefore

def test_USDC_to_WETH_exact_in_static_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["USDC"].transfer(mockVault, 2000e6, {"from": env.whales["USDC"]})

    trade = univ2_trade_exact_in_single(
        env, 
        env.tokens["USDC"].address, 
        env.tokens["WETH"].address, 
        env.tokens["USDC"].balanceOf(mockVault), 
        Wei(1e18)
    )

    # Vault does not have permission to sell USDC
    with brownie.reverts():
        mockVault.executeTrade.call(DEX_ID["UNISWAP_V2"], trade, {"from": accounts[0]})

    # Give vault permission to sell USDC
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["USDC"].address, 
        [True, set_dex_flags(0, UNISWAP_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    
    # Slippage too high
    with brownie.reverts():
        badTrade = univ2_trade_exact_in_single(
            env, 
            env.tokens["USDC"].address, 
            env.tokens["WETH"].address, 
            env.tokens["USDC"].balanceOf(mockVault), 
            Wei(5e18)
        )
        mockVault.executeTrade(DEX_ID["UNISWAP_V2"], badTrade, {"from": accounts[0]})

    usdcBefore = env.tokens["USDC"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTrade(DEX_ID["UNISWAP_V2"], trade, {"from": accounts[0]})
    assert env.tokens["USDC"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == usdcBefore - env.tokens["USDC"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore
