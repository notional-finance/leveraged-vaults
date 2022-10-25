import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, accounts, network, MockVault
from brownie.convert import to_bytes
from brownie.network.state import Chain
from scripts.common import DEX_ID, TRADE_TYPE
from scripts.EnvironmentConfig import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def balancer_trade_exact_in(sellToken, buyToken, amount, poolId):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        sellToken, 
        buyToken, 
        amount, 
        0, 
        deadline, 
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes(poolId, "bytes32")]]
        )
    ]

def test_wstETH_to_WETH_exact_in_single():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["wstETH"].transfer(mockVault, 1e18, {"from": env.whales["wstETH"]})

    trade = balancer_trade_exact_in(
        env.tokens["wstETH"].address, 
        env.tokens["WETH"].address, 
        env.tokens["wstETH"].balanceOf(mockVault),
        "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080"
    )

    # Vault does not have permission to sell wstETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell wstETH
    env.tradingModule.setTokenPermissions(mockVault.address, env.tokens["wstETH"].address, [True], 
        {"from": env.notional.owner()})

    wstETHBefore = env.tokens["wstETH"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})
    assert ret.return_value[0] == wstETHBefore - env.tokens["wstETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore

def test_wstETH_to_ETH_exact_in_single():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["wstETH"].transfer(mockVault, 1e18, {"from": env.whales["wstETH"]})

    trade = balancer_trade_exact_in(
        env.tokens["wstETH"].address, 
        ZERO_ADDRESS, 
        env.tokens["wstETH"].balanceOf(mockVault),
        "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080"
    )

    # Vault does not have permission to sell wstETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell wstETH
    env.tradingModule.setTokenPermissions(mockVault.address, env.tokens["wstETH"].address, [True], 
        {"from": env.notional.owner()})

    wstETHBefore = env.tokens["wstETH"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})
    assert ret.return_value[0] == wstETHBefore - env.tokens["wstETH"].balanceOf(mockVault)
    assert ret.return_value[1] == mockVault.balance() - ethBefore

def test_WETH_to_wstETH_exact_in_single():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["WETH"].transfer(mockVault, 1e18, {"from": env.whales["WETH"]})

    trade = balancer_trade_exact_in(
        env.tokens["WETH"].address, 
        env.tokens["wstETH"].address, 
        env.tokens["WETH"].balanceOf(mockVault),
        "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080"
    )

    # Vault does not have permission to sell WETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell WETH
    env.tradingModule.setTokenPermissions(mockVault.address, env.tokens["WETH"].address, [True], 
        {"from": env.notional.owner()})

    wstETHBefore = env.tokens["wstETH"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})
    assert ret.return_value[0] == wethBefore - env.tokens["WETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["wstETH"].balanceOf(mockVault) - wstETHBefore

def test_ETH_to_wstETH_exact_in_single():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.whales["ETH_EOA"].transfer(mockVault, 1e18)

    trade = balancer_trade_exact_in(
        ZERO_ADDRESS, 
        env.tokens["wstETH"].address, 
        mockVault.balance(),
        "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080"
    )

    # Vault does not have permission to sell WETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell WETH
    env.tradingModule.setTokenPermissions(mockVault.address, ZERO_ADDRESS, [True], 
        {"from": env.notional.owner()})

    wstETHBefore = env.tokens["wstETH"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})
    assert ret.return_value[0] == ethBefore - mockVault.balance()
    assert ret.return_value[1] == env.tokens["wstETH"].balanceOf(mockVault) - wstETHBefore
