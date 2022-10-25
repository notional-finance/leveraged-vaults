
import pytest
import brownie
from brownie import accounts, network, MockVault
from brownie.network.state import Chain
from scripts.common import DEX_ID, TRADE_TYPE, get_univ3_single_data
from scripts.EnvironmentConfig import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def univ3_trade_exact_in_single(sellToken, buyToken, amount, fee):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_SINGLE"], sellToken, buyToken, amount, 0, deadline, get_univ3_single_data(fee)
    ]

def test_stETH_to_weth():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["stETH"].transfer(mockVault, 1e18, {"from": env.whales["stETH"]})

    trade = univ3_trade_exact_in_single(
        env.tokens["stETH"].address, env.tokens["WETH"].address, env.tokens["stETH"].balanceOf(mockVault), 3000
    )

    # Vault does not have permission to sell stETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell stETH
    env.tradingModule.setTokenPermissions(mockVault.address, env.tokens["stETH"].address, [True], 
        {"from": env.notional.owner()})

    stETHBalBefore = env.tokens["stETH"].balanceOf(mockVault)
    wethBalBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})
    assert ret.return_value[0] == stETHBalBefore - env.tokens["stETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBalBefore

def test_weth_to_stETH():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["WETH"].transfer(mockVault, 1e18, {"from": env.whales["WETH"]})

    trade = univ3_trade_exact_in_single(
        env.tokens["WETH"].address, env.tokens["stETH"].address, env.tokens["WETH"].balanceOf(mockVault), 3000
    )

    # Vault does not have permission to sell WETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["UNISWAP_V3"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell WETH
    env.tradingModule.setTokenPermissions(mockVault.address, env.tokens["WETH"].address, [True], 
        {"from": env.notional.owner()})

    stETHBalBefore = env.tokens["stETH"].balanceOf(mockVault)
    wethBalBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})
    assert ret.return_value[0] == wethBalBefore - env.tokens["WETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["stETH"].balanceOf(mockVault) - stETHBalBefore
