
import pytest
import brownie
from brownie import accounts, network, MockVault
from brownie.network.state import Chain
from scripts.common import DEX_ID, TRADE_TYPE, get_dynamic_trade_params
from scripts.EnvironmentConfig import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def test_stETH_to_weth():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["stETH"].transfer(mockVault, 100e18, {"from": env.whales["stETH"]})

    trade = [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        env.tokens["stETH"].address, 
        env.tokens["WETH"].address, 
        1e18, 
        0, 
        chain.time() + 20000,
        bytes()
    ]

    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})

    env.tradingModule.setTokenPermissions(mockVault.address, env.tokens["stETH"].address, [True], 
        {"from": env.notional.owner()})

    stETHBalBefore = env.tokens["stETH"].balanceOf(mockVault)
    wethBalBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["CURVE"], trade, 5e6, {"from": accounts[0]})
    assert ret.return_value[0] == stETHBalBefore - env.tokens["stETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBalBefore

def test_weth_to_stETH():
    pass