import pytest
import eth_abi
from brownie import (
    Weighted2TokenAuraVault, 
    MetaStable2TokenAuraVault,
    Boosted3TokenAuraVault,
    MockStable2TokenAuraVault,
    MockWeighted2TokenAuraVault, 
    MockBoosted3TokenAuraVault
)
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
def StratStableETHstETH():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("StratStableETHstETH", MetaStable2TokenAuraVault)
    mock = MockStable2TokenAuraVault.deploy(vault.getStrategyContext(), {"from": env.deployer})
    return (env, vault, mock)

@pytest.fixture()
def StratBoostedPoolDAIPrimary():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("StratBoostedPoolDAIPrimary", Boosted3TokenAuraVault)
    mock = MockBoosted3TokenAuraVault.deploy(vault.getStrategyContext(), {"from": env.deployer})
    return (env, vault, mock)

@pytest.fixture()
def StratBoostedPoolUSDCPrimary():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("StratBoostedPoolUSDCPrimary", Boosted3TokenAuraVault)
    mock = MockBoosted3TokenAuraVault.deploy(vault.getStrategyContext(), {"from": env.deployer})
    return (env, vault, mock)
