import pytest
from brownie import interface
from brownie.network.state import Chain
from scripts.common import set_dex_flags, set_trade_type_flags
from tests.trading.helpers import balancer_trade_exact_in_single

chain = Chain()

def test_get_spot_price(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    spotPrice0 = vault.getSpotPrice(0)/1e18
    spotPrice1 = vault.getSpotPrice(1)/1e18
    assert pytest.approx((1/spotPrice1)/spotPrice0, rel=1e-35) == 1

def test_spot_price_within_1_perc_of_pair_price_after_trading(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    poolId = vault.getStrategyContext()["poolContext"]['poolId']
    pool = vault.getStrategyContext()["poolContext"]["basePool"]["poolToken"]        
    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        env.tokens["wstETH"].address, 
        [
            True, 
            set_dex_flags(0, BALANCER_V2=True, CURVE=True), 
            set_trade_type_flags(0, EXACT_IN_SINGLE=True)
        ], 
        {"from": env.notional.owner()}
    )
    env.tradingModule.setTokenPermissions(
        env.tradingModule.address, 
        env.tokens["WETH"].address, 
        [
            True, 
            set_dex_flags(0, BALANCER_V2=True), 
            set_trade_type_flags(0, EXACT_IN_SINGLE=True)
        ], 
        {"from": env.notional.owner()}
    )

    # Trade
    env.tokens["wstETH"].transfer(env.tradingModule, 30000e18, {"from": env.whales["wstETH"]})
    tradeCallData = balancer_trade_exact_in_single(
        env.tokens["wstETH"].address, env.tokens["WETH"].address, 30000e18, 0, poolId
    )

    env.tradingModule.executeTradeWithDynamicSlippage(4, tradeCallData, 5e6, {"from": env.whales["wstETH"]})

    # Trade in small increments to update the balancer oracle pair price 
    for i in range(0,10):
        env.tokens["wstETH"].transfer(env.tradingModule, 1e18, {"from": env.whales["wstETH"]})
        tradeCallData = balancer_trade_exact_in_single(env.tokens["wstETH"].address, env.tokens["WETH"].address, 1e18, 0, poolId)
        env.tradingModule.executeTradeWithDynamicSlippage(4, tradeCallData, 10e6, {"from": env.whales["wstETH"]})
        tradeCallData = balancer_trade_exact_in_single(env.tokens["WETH"].address, env.tokens["wstETH"].address, 1e18, 0, poolId)
        env.tradingModule.executeTradeWithDynamicSlippage(4, tradeCallData, 10e6, {"from": env.whales["wstETH"]})
        chain.sleep(60)

    secondaryScaleFactor = vault.getStrategyContext()["poolContext"]["secondaryScaleFactor"]/1e18
    spotPrice0 = vault.getSpotPrice(0)/1e18
    pairPrice = interface.IPriceOracle(pool).getLatest(0)/1e18
    balancerPrice = 1/(pairPrice * secondaryScaleFactor)
    assert pytest.approx(spotPrice0/balancerPrice, rel=1e-2) == 1