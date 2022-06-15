import pytest
import eth_abi
from brownie import ZERO_ADDRESS
from brownie.network.state import Chain
from brownie.convert import to_bytes
from scripts.trading.environment import (
    EnvironmentConfig,
    TestAccounts, 
    Environment, 
    TradeType, 
    DexId,
    interface
)

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

def test_exact_in_single_eth_token():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)
    testAccounts.ETHWhale.transfer(env.mockVault.address, 10e18)
    trade = [
        TradeType["EXACT_IN_SINGLE"], 
        ZERO_ADDRESS, 
        EnvironmentConfig["DAI"], 
        1e18, 
        0, 
        chain.time() + 20000,
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a", "bytes32")]]
        )
    ]

    dai = interface.IERC20(EnvironmentConfig["DAI"])

    assert env.mockVault.balance() == 10e18
    assert dai.balanceOf(env.mockVault) == 0

    env.mockVault.executeTrade(
        DexId["BALANCER_V2"], 
        trade,
        {"from": testAccounts.ETHWhale}
    )

    assert env.mockVault.balance() == 9e18
    assert pytest.approx(dai.balanceOf(env.mockVault), abs=1000) == 1804175391328282697475

def test_exact_in_single_token_eth():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)
    trade = [
        TradeType["EXACT_IN_SINGLE"],  
        EnvironmentConfig["DAI"], 
        ZERO_ADDRESS,
        1000e18, 
        0, 
        chain.time() + 20000,
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a", "bytes32")]]
        )
    ]

    dai = interface.IERC20(EnvironmentConfig["DAI"])
    dai.transfer(env.mockVault.address, 1000e18, {"from": testAccounts.DAIWhale})

    assert env.mockVault.balance() == 0
    assert dai.balanceOf(env.mockVault) == 1000e18

    env.mockVault.executeTrade(
        DexId["BALANCER_V2"], 
        trade,
        {"from": testAccounts.ETHWhale}
    )

    assert pytest.approx(env.mockVault.balance(), abs=1000) == 553603061791307204
    assert pytest.approx(dai.balanceOf(env.mockVault), abs=1000) == 0

def test_exact_in_single_token_token():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)
    trade = [
        TradeType["EXACT_IN_SINGLE"],  
        EnvironmentConfig["DAI"], 
        EnvironmentConfig["USDC"],
        1000e18, 
        0, 
        chain.time() + 20000,
        eth_abi.encode_abi(
            ["(bytes32)"],
            [[to_bytes("0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063", "bytes32")]]
        )
    ]

    dai = interface.IERC20(EnvironmentConfig["DAI"])
    dai.transfer(env.mockVault.address, 1000e18, {"from": testAccounts.DAIWhale})
    usdc = interface.IERC20(EnvironmentConfig["USDC"])

    assert usdc.balanceOf(env.mockVault) == 0
    assert dai.balanceOf(env.mockVault) == 1000e18

    env.mockVault.executeTrade(
        DexId["BALANCER_V2"], 
        trade,
        {"from": testAccounts.ETHWhale}
    )

    assert pytest.approx(usdc.balanceOf(env.mockVault), abs=100) == 999892561
    assert pytest.approx(dai.balanceOf(env.mockVault), abs=1000) == 0

def test_exact_out_single_eth_token():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)

def test_exact_out_single_token_eth():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)

def test_exact_out_single_token_token():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)

def test_exact_in_batch():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)
    pass

def test_exact_out_batch():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)
    pass

