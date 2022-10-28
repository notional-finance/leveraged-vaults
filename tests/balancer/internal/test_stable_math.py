import pytest

def test_get_spot_price(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    spotPrice0 = vault.getSpotPrice(0)/1e18
    spotPrice1 = vault.getSpotPrice(1)/1e18
    assert pytest.approx((1/spotPrice1)/spotPrice0, rel=1e-5) == 1

def test_get_spot_price_positive_trend():
    pass

def test_get_spot_price_negative_trend():
    pass
