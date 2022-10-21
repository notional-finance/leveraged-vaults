import pytest
import eth_abi
from brownie import (
    MockMetaStable2TokenAuraVault,
    MockBoosted3TokenAuraVault,
    MetaStable2TokenAuraHelper,
    Boosted3TokenAuraHelper
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
    vault = env.deployBalancerVault("StratStableETHstETH", MockMetaStable2TokenAuraVault, [MetaStable2TokenAuraHelper])
    return (env, vault)

@pytest.fixture()
def StratBoostedPoolDAIPrimary():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("StratBoostedPoolDAIPrimary", MockBoosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    return (env, vault)

@pytest.fixture()
def StratBoostedPoolUSDCPrimary():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("StratBoostedPoolUSDCPrimary", MockBoosted3TokenAuraVault, [Boosted3TokenAuraHelper])
    return (env, vault)
