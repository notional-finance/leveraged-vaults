import pytest
import eth_abi
import brownie
from brownie import Wei, ZERO_ADDRESS, accounts, network, MockVault
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

def balancer_trade_exact_in_single(sellToken, buyToken, amount, poolId):
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

def balancer_trade_exact_in_batch(sellToken, buyToken, amount, swaps, assets, limits):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_BATCH"], 
        sellToken, 
        buyToken, 
        amount, 
        0, 
        deadline, 
        eth_abi.encode_abi(
            ['((bytes32,uint256,uint256,uint256,bytes)[],address[],int256[])'],
            [[swaps, assets, limits]]
        )
    ]    

def test_wstETH_to_WETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["wstETH"].transfer(mockVault, 1e18, {"from": env.whales["wstETH"]})

    trade = balancer_trade_exact_in_single(
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
    assert env.tokens["wstETH"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == wstETHBefore - env.tokens["wstETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore

def test_wstETH_to_ETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["wstETH"].transfer(mockVault, 1e18, {"from": env.whales["wstETH"]})

    trade = balancer_trade_exact_in_single(
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
    assert env.tokens["wstETH"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == wstETHBefore - env.tokens["wstETH"].balanceOf(mockVault)
    assert ret.return_value[1] == mockVault.balance() - ethBefore

def test_WETH_to_wstETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["WETH"].transfer(mockVault, 1e18, {"from": env.whales["WETH"]})

    trade = balancer_trade_exact_in_single(
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
    assert env.tokens["WETH"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == wethBefore - env.tokens["WETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["wstETH"].balanceOf(mockVault) - wstETHBefore

def test_ETH_to_wstETH_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.whales["ETH_EOA"].transfer(mockVault, 1e18)

    trade = balancer_trade_exact_in_single(
        ZERO_ADDRESS, 
        env.tokens["wstETH"].address, 
        mockVault.balance(),
        "0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080"
    )

    # Vault does not have permission to sell ETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell ETH
    env.tradingModule.setTokenPermissions(mockVault.address, ZERO_ADDRESS, [True], 
        {"from": env.notional.owner()})

    wstETHBefore = env.tokens["wstETH"].balanceOf(mockVault)
    ethBefore = mockVault.balance()
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})
    assert mockVault.balance() == 0
    assert ret.return_value[0] == ethBefore - mockVault.balance()
    assert ret.return_value[1] == env.tokens["wstETH"].balanceOf(mockVault) - wstETHBefore

def test_wstETH_to_WETH_to_DAI_exact_in_dynamic_slippage():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["wstETH"].transfer(mockVault, 1e18, {"from": env.whales["wstETH"]})

    sellAmount = env.tokens["wstETH"].balanceOf(mockVault)
    trade = balancer_trade_exact_in_batch(
        env.tokens["wstETH"].address, 
        env.tokens["DAI"].address, 
        sellAmount,
        [
            # wstETh -> ETH
            [
                to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32"),
                0,
                1,
                sellAmount,
                bytes()
            ],
            # ETH -> DAI
            [
                to_bytes("0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a", "bytes32"),
                1,
                2,
                0, # Entire amount from previous swap
                bytes()
            ]
        ],
        [env.tokens["wstETH"].address, env.tokens["WETH"].address, env.tokens["DAI"].address],
        [sellAmount, 0, 0]
    )
    # Vault does not have permission to sell ETH
    with brownie.reverts():
        mockVault.executeTradeWithDynamicSlippage.call(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})

    # Give vault permission to sell ETH
    env.tradingModule.setTokenPermissions(mockVault.address, env.tokens["wstETH"], [True], 
        {"from": env.notional.owner()})

    wstETHBefore = env.tokens["wstETH"].balanceOf(mockVault)
    daiBefore = env.tokens["DAI"].balanceOf(mockVault)
    ret = mockVault.executeTradeWithDynamicSlippage(DEX_ID["BALANCER_V2"], trade, 5e6, {"from": accounts[0]})
    assert mockVault.balance() == 0
    assert ret.return_value[0] == wstETHBefore - env.tokens["wstETH"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["DAI"].balanceOf(mockVault) - daiBefore
