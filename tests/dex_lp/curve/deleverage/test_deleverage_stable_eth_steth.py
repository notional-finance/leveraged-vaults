import pytest
from brownie import Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.dex_lp.helpers import enterMaturity, get_metastable_amounts
from scripts.common import (
    get_redeem_params, 
    get_dynamic_trade_params, 
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_success(StratCurveStableETHstETH):
    (env, vault, mock) = StratCurveStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 150e8
    depositAmount = 20e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    enterMaturity(env, mock, currencyId, maturity, depositAmount, primaryBorrowAmount, accounts[0])
    mock.setValuationFactor(accounts[0], 0.8e8, {"from": accounts[0]})
    collateralInfo = env.notional.getVaultAccountCollateralRatio(accounts[0], mock.address)

    # Should be undercollateralized
    assert collateralInfo["collateralRatio"] < collateralInfo["minCollateralRatio"]

    # Manipulation the valuation factor causes the vault to transfer extra tokens
    # to the liquidator. We keep track of this for the comparison at the end.
    vaultSharesToLiquidator = collateralInfo["vaultSharesToLiquidator"]
    valuationFixBefore = mock.convertStrategyToUnderlying(accounts[0], vaultSharesToLiquidator, maturity)
    mock.setValuationFactor(accounts[0], 1e8, {"from": accounts[0]})
    valuationFixAfter = mock.convertStrategyToUnderlying(accounts[0], vaultSharesToLiquidator, maturity)
    mock.setValuationFactor(accounts[0], 0.8e8, {"from": accounts[0]})
    valuationFix = valuationFixAfter - valuationFixBefore

    assetAmountFromLiquidator = collateralInfo["maxLiquidatorDepositAssetCash"]
    vaultState = env.notional.getVaultState(mock, maturity)
    assetRate = env.notional.getCurrencyAndRates(currencyId)["assetRate"]
    strategyTokensToRedeem = vaultSharesToLiquidator / vaultState["totalVaultShares"] * vaultState["totalStrategyTokens"]
    underlyingRedeemed = mock.convertStrategyToUnderlying(accounts[0], strategyTokensToRedeem, maturity)
    flashLoanAmount = assetRate["rate"] * assetAmountFromLiquidator / assetRate["underlyingDecimals"]
    #primaryAmount, secondaryAmount = get_metastable_amounts(mock.getStrategyContext()["poolContext"], underlyingRedeemed)
    # discount primary and secondary slightly
    redeemParams = get_redeem_params(underlyingRedeemed * 0.98, 0)
    assert env.tokens["WETH"].balanceOf(env.liquidator.owner()) == 0
    env.liquidator.flashLiquidate(
        env.tokens["WETH"], 
        Wei(flashLoanAmount * 1.2), 
        [1, accounts[0].address, mock.address, False, redeemParams], 
        {"from": env.liquidator.owner()}
    )

    # 0.02 == liquidation discount
    expectedProfit = valuationFix + underlyingRedeemed * 0.02
    assert pytest.approx(env.tokens["WETH"].balanceOf(env.liquidator.owner()), rel=5e-2) == expectedProfit
