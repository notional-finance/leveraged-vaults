import pytest
import eth_abi
from brownie import (Weighted2TokenAuraVault, MetaStable2TokenAuraVault)
from brownie import network, Wei
from tests.fixtures import *
from scripts.BalancerEnvironment import getEnvironment

@pytest.fixture(scope="module", autouse=True)
def Strat50ETH50USDC():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("Strat50ETH50USDC", Weighted2TokenAuraVault)
    return (env, vault)

@pytest.fixture(scope="module", autouse=True)
def StratStableETHstETH():
    env = getEnvironment(network.show_active())
    vault = env.deployBalancerVault("StratStableETHstETH", MetaStable2TokenAuraVault)
    return (env, vault)

def test_bpt_valuation_2token_weighted_50_50_primary_first():
    pass

def test_bpt_valuation_2token_weighted_50_50_primary_second(Strat50ETH50USDC):
    pass

def test_bpt_valuation_2token_weighted_80_20_primary_first():
    pass

def test_bpt_valuation_2token_weighted_80_20_primary_second():
    pass

def test_bpt_valuation_2token_metastable_primary_first():
    pass

def test_bpt_valuation_2token_metastable_primary_second(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    env.whales["ETH"].transfer(env.mockTwoTokenAuraStrategyUtils.address, 5e18)
    strategyContext = vault.getStrategyContext()
    bptAmount = env.mockTwoTokenAuraStrategyUtils.joinPoolAndStake.call(
        strategyContext["baseContext"], 
        strategyContext["stakingContext"], 
        strategyContext["poolContext"], 
        2e18, # 2 ETH primary
        0, # no secondary
        0 # minBPT
    )
    assert pytest.approx(bptAmount, abs=1000) == 1982105365727602511
    bptInPrimaryBalance = env.mockTwoTokenPoolUtils.getTimeWeightedPrimaryBalance(
        strategyContext["poolContext"], 
        strategyContext["oracleContext"]["baseContext"],
        bptAmount
    )
    # BPT value should be below deposit amount
    assert bptInPrimaryBalance <= 2e18
    assert pytest.approx(bptInPrimaryBalance, abs=1000) == 1974982615054763315

