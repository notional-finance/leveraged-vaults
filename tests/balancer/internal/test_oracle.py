import pytest
from tests.fixtures import *

def test_bpt_valuation_2token_metastable_primary_second(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    env.whales["ETH"].transfer(mock.address, 5e18)
    bptAmount = mock.joinPoolAndStake.call(2e18, 0, 0)
    assert pytest.approx(bptAmount, rel=1e-3) == 1982105365727602511
    actualBPTValueInPrimary = mock.getTimeWeightedPrimaryBalance(bptAmount)
    # 5% variation due to oracle price
    assert pytest.approx(actualBPTValueInPrimary, rel=5e-2) == 2e18

