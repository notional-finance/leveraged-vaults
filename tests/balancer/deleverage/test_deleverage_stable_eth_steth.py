import pytest
from brownie import Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, check_invariant
from scripts.common import (
    get_redeem_params, 
    get_dynamic_trade_params, 
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_low_leverage_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vault.setValuationFactor(0.8e8, {"from": accounts[0]})
    assetAmountFromLiquidator = env.notional.getVaultAccountCollateralRatio(accounts[0], vault.address)[2]
    assetRate = env.notional.getCurrencyAndRates(1)["assetRate"]
    flashLoanAmount = assetRate["rate"] * assetAmountFromLiquidator / assetRate["underlyingDecimals"]
    # getSpotBalances
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    assert env.tokens["WETH"].balanceOf(env.liquidator.owner()) == 0
    env.liquidator.flashLiquidate(
        env.tokens["WETH"], 
        Wei(flashLoanAmount * 1.2), 
        [1, accounts[0].address, vault.address, redeemParams], 
        {"from": env.liquidator.owner()}
    )
    assert pytest.approx(env.tokens["WETH"].balanceOf(env.liquidator.owner()), rel=1e-4) == 8007301938986759866
