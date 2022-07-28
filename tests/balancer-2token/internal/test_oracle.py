import pytest
from tests.fixtures import *

def test_get_optimal_secondary_amount_weighted(Strat50ETH50USDC):
    (env, vault, mockTwoTokenAuraStrategyUtils) = Strat50ETH50USDC
    env.whales["ETH"].transfer(mockTwoTokenAuraStrategyUtils.address, 500e18)
    env.tokens["USDC"].transfer(mockTwoTokenAuraStrategyUtils.address, 500000e6, {"from": env.whales["USDC"]})
    strategyContext = vault.getStrategyContext()
    primaryAmount = 300e18
    secondaryAmount = env.mockWeighted2TokenOracleMath.getOptimalSecondaryBorrowAmount(
                    strategyContext["oracleContext"],
                    strategyContext["poolContext"],
                    primaryAmount)
    spotPriceBefore = env.mockWeighted2TokenOracleMath.getSpotPrice(
        strategyContext["oracleContext"],
        strategyContext["poolContext"],
        0
    )
    mockTwoTokenAuraStrategyUtils.joinPoolAndStake(
        strategyContext["baseStrategy"], 
        strategyContext["stakingContext"], 
        strategyContext["poolContext"], 
        primaryAmount, 
        secondaryAmount, 
        0
    )
    strategyContext = vault.getStrategyContext()
    spotPriceAfter = env.mockWeighted2TokenOracleMath.getSpotPrice(
        strategyContext["oracleContext"],
        strategyContext["poolContext"],
        0
    )
    assert pytest.approx(spotPriceBefore, rel=1e-3) == spotPriceAfter

def test_get_optimal_secondary_amount_stable(StratStableETHstETH):
    (env, vault, mockTwoTokenAuraStrategyUtils) = StratStableETHstETH
    env.whales["ETH"].transfer(mockTwoTokenAuraStrategyUtils.address, 500e18)
    env.tokens["wstETH"].transfer(mockTwoTokenAuraStrategyUtils.address, 1000e18, {"from": env.whales["wstETH"]})
    strategyContext = vault.getStrategyContext()
    primaryAmount = 300e18
    secondaryAmount = env.mockStable2TokenOracleMath.getOptimalSecondaryBorrowAmount(
                    strategyContext["oracleContext"],
                    strategyContext["poolContext"],
                    primaryAmount)
    spotPriceBefore = env.mockStable2TokenOracleMath.getSpotPrice(
        strategyContext["oracleContext"],
        strategyContext["poolContext"],
        0
    )
    mockTwoTokenAuraStrategyUtils.joinPoolAndStake(
        strategyContext["baseStrategy"], 
        strategyContext["stakingContext"], 
        strategyContext["poolContext"], 
        primaryAmount, 
        secondaryAmount, 
        0
    )
    strategyContext = vault.getStrategyContext()
    spotPriceAfter = env.mockStable2TokenOracleMath.getSpotPrice(
        strategyContext["oracleContext"],
        strategyContext["poolContext"],
        0
    )
    assert pytest.approx(spotPriceBefore, rel=1e-8) == spotPriceAfter


def test_bpt_valuation_2token_weighted_50_50_primary_first():
    pass

def test_bpt_valuation_2token_weighted_50_50_primary_second(Strat50ETH50USDC):
    (env, vault, mockTwoTokenAuraStrategyUtils) = Strat50ETH50USDC
    env.whales["ETH"].transfer(mockTwoTokenAuraStrategyUtils.address, 5e18)
    env.tokens["USDC"].transfer(mockTwoTokenAuraStrategyUtils.address, 5000e6, {"from": env.whales["USDC"]})
    strategyContext = vault.getStrategyContext()
    primaryAmount = 2e18 # 2 ETH primary
    optimalSecondaryAmount = env.mockWeighted2TokenOracleMath.getOptimalSecondaryBorrowAmount(
        strategyContext["oracleContext"], 
        strategyContext["poolContext"], 
        2e18
    )
    bptAmount = mockTwoTokenAuraStrategyUtils.joinPoolAndStake.call(
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
    (env, vault, mockTwoTokenAuraStrategyUtils) = StratStableETHstETH
    env.whales["ETH"].transfer(mockTwoTokenAuraStrategyUtils.address, 5e18)
    strategyContext = vault.getStrategyContext()
    bptAmount = mockTwoTokenAuraStrategyUtils.joinPoolAndStake.call(
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
    # 5% variation due to oracle price
    assert pytest.approx(actualBPTValueInPrimary, rel=5e-2) == 2e18

