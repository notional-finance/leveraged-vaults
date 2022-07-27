import pytest
import eth_abi
from brownie import (Weighted2TokenAuraVault, MetaStable2TokenAuraVault, MockTwoTokenAuraStrategyUtils)
from brownie.network import Chain
from brownie import network, Contract
from scripts.BalancerEnvironment import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

@pytest.fixture()
def Strat50ETH50USDC():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("Strat50ETH50USDC", Weighted2TokenAuraVault)
    strategyContext = vault.getStrategyContext()
    mockTwoTokenAuraStrategyUtils = MockTwoTokenAuraStrategyUtils.deploy(
        strategyContext["poolContext"],
        strategyContext["stakingContext"],
        {"from": env.deployer}
    )
    return (env, vault, mockTwoTokenAuraStrategyUtils)

@pytest.fixture()
def StratStableETHstETH():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("StratStableETHstETH", MetaStable2TokenAuraVault)
    strategyContext = vault.getStrategyContext()
    mockTwoTokenAuraStrategyUtils = MockTwoTokenAuraStrategyUtils.deploy(
        strategyContext["poolContext"],
        strategyContext["stakingContext"],
        {"from": env.deployer}
    )
    return (env, vault, mockTwoTokenAuraStrategyUtils)
