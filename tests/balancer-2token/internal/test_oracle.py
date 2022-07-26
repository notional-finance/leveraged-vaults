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
    (env, vault) = Strat50ETH50USDC
    env.whales["ETH"].transfer(env.mockTwoTokenAuraStrategyUtils.address, 5e18)
    env.tokens["USDC"].transfer(env.mockTwoTokenAuraStrategyUtils.address, 5000e6, {"from": env.whales["USDC"]})
    strategyContext = vault.getStrategyContext()
    primaryAmount = 2e18 # 2 ETH primary
    optimalSecondaryAmount = env.mockWeighted2TokenOracleMath.getOptimalSecondaryBorrowAmount(
        strategyContext["oracleContext"], 
        strategyContext["poolContext"], 
        2e18
    )
    bptAmount = env.mockTwoTokenAuraStrategyUtils.joinPoolAndStake.call(
        strategyContext["baseStrategy"], 
        strategyContext["stakingContext"], 
        strategyContext["poolContext"], 
        primaryAmount,
        optimalSecondaryAmount,
        0 # minBPT
    )
    assert pytest.approx(bptAmount, rel=1e-3) == 141918354376395549771
    # BPT value calculated based on oracle price
    actualBPTValueInPrimary = env.mockTwoTokenPoolUtils.getTimeWeightedPrimaryBalance(
        strategyContext["poolContext"], 
        strategyContext["oracleContext"]["baseOracle"],
        bptAmount
    )
    spotPrice = env.mockWeighted2TokenOracleMath.getSpotPrice(
        strategyContext["oracleContext"],
        strategyContext["poolContext"],
        1
    )
    # Normalize optimalSecondaryAmount to 18 decimals
    optimalSecondaryAmount = optimalSecondaryAmount * 1e18 / 1e6
    # BPT value calculated based on spot price
    expectedBPTValueInPrimary = optimalSecondaryAmount * 1e18 / spotPrice + primaryAmount
    # 0.5% tolerance
    assert pytest.approx(actualBPTValueInPrimary, rel=5e-3) == expectedBPTValueInPrimary

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
        strategyContext["baseStrategy"], 
        strategyContext["stakingContext"], 
        strategyContext["poolContext"], 
        2e18, # 2 ETH primary
        0, # no secondary
        0 # minBPT
    )
    assert pytest.approx(bptAmount, rel=1e-3) == 1982105365727602511
    actualBPTValueInPrimary = env.mockTwoTokenPoolUtils.getTimeWeightedPrimaryBalance(
        strategyContext["poolContext"], 
        strategyContext["oracleContext"]["baseOracle"],
        bptAmount
    )
    spotPrice = env.mockStable2TokenOracleMath.getSpotPrice(
        strategyContext["oracleContext"],
        strategyContext["poolContext"],
        1
    )    
    assert pytest.approx(actualBPTValueInPrimary, abs=1000) == 2054761115742549740

