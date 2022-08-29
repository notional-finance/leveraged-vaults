import pytest
from tests.fixtures import *

def test_get_optimal_secondary_amount_weighted(Strat50ETH50USDC):
    (env, vault, mock) = Strat50ETH50USDC
    env.whales["ETH"].transfer(mock.address, 500e18)
    env.tokens["USDC"].transfer(mock.address, 500000e6, {"from": env.whales["USDC"]})
    primaryAmount = 300e18
    secondaryAmount = mock.getOptimalSecondaryBorrowAmount(primaryAmount)
    spotPriceBefore = mock.getSpotPrice(0)
    mock.joinPoolAndStake(primaryAmount, secondaryAmount, 0, {"from": env.whales["USDC"]})
    spotPriceAfter = mock.getSpotPrice(0)
    assert pytest.approx(spotPriceBefore, rel=1e-3) == spotPriceAfter

def test_get_optimal_secondary_amount_stable(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    env.whales["ETH"].transfer(mock.address, 500e18)
    env.tokens["wstETH"].transfer(mock.address, 1000e18, {"from": env.whales["wstETH"]})
    primaryAmount = 300e18
    secondaryAmount = mock.getOptimalSecondaryBorrowAmount(primaryAmount)
    spotPriceBefore = mock.getSpotPrice(0)
    mock.joinPoolAndStake(primaryAmount, secondaryAmount, 0)
    spotPriceAfter = mock.getSpotPrice(0)
    assert pytest.approx(spotPriceBefore, rel=1e-8) == spotPriceAfter


def test_bpt_valuation_2token_weighted_50_50_primary_first():
    pass

def test_bpt_valuation_2token_weighted_50_50_primary_second(Strat50ETH50USDC):
    (env, vault, mock) = Strat50ETH50USDC
    env.whales["ETH"].transfer(mock.address, 5e18)
    env.tokens["USDC"].transfer(mock.address, 5000e6, {"from": env.whales["USDC"]})
    primaryAmount = 2e18 # 2 ETH primary
    optimalSecondaryAmount = mock.getOptimalSecondaryBorrowAmount(2e18)
    bptAmount = mock.joinPoolAndStake.call(primaryAmount, optimalSecondaryAmount, 0) # minBPT
    assert pytest.approx(bptAmount, rel=1e-3) == 141918354376395549771
    # BPT value calculated based on oracle price
    actualBPTValueInPrimary = mock.getTimeWeightedPrimaryBalance(bptAmount)
    spotPrice = mock.getSpotPrice(1)
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
    (env, vault, mock) = StratStableETHstETH
    env.whales["ETH"].transfer(mock.address, 5e18)
    bptAmount = mock.joinPoolAndStake.call(2e18, 0, 0)
    assert pytest.approx(bptAmount, rel=1e-3) == 1982105365727602511
    actualBPTValueInPrimary = mock.getTimeWeightedPrimaryBalance(bptAmount)
    # 5% variation due to oracle price
    assert pytest.approx(actualBPTValueInPrimary, rel=5e-2) == 2e18

