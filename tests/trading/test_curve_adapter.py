
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

def test_stETH_to_weth():
    testAccounts = TestAccounts()
    env = Environment(testAccounts.ETHWhale)
    stETH = interface.IERC20(EnvironmentConfig["stETH"])
    weth = interface.IERC20(EnvironmentConfig["WETH"])

    stETH.transfer(env.mockVault.address, 100e18, {"from": testAccounts.stETHWhale})

    trade = [
        TradeType["EXACT_IN_SINGLE"], 
        stETH.address, 
        weth.address, 
        1e18, 
        0, 
        chain.time() + 20000,
        bytes()
    ]

    env.mockVault.executeTrade(
        DexId["CURVE"], 
        trade,
        {"from": testAccounts.ETHWhale}
    )

def test_weth_to_stETH():
    pass