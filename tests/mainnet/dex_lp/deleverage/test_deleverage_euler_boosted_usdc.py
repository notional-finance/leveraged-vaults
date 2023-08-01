import pytest
from brownie import Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, get_asset_exchange_rate
from scripts.common import (
    get_redeem_params, 
    get_dynamic_trade_params, 
    get_univ3_single_data,
    DEX_ID,
    TRADE_TYPE
)
from tests.balancer.acceptance import (
    USDCPrimaryContext
)

chain = Chain()

def test_single_maturity_success(StratEulerBoostedPoolUSDCPrimary):
    (env, vault, mock) = StratEulerBoostedPoolUSDCPrimary
    context = USDCPrimaryContext(*StratEulerBoostedPoolUSDCPrimary)
    currencyId = 3
    primaryBorrowAmount = 40000e8
    depositAmount = 10000e6
    context.transfer(accounts[0], depositAmount)
    context.approve(accounts[0], env.notional.address)
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
    flashLoanAmount = assetAmountFromLiquidator * get_asset_exchange_rate(env, currencyId) * assetRate["underlyingDecimals"] / 1e8
    # discount primary slightly
    redeemParams = get_redeem_params(underlyingRedeemed * 0.98, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    usdcBefore = env.tokens["USDC"].balanceOf(env.aaveLiquidator.owner())

    env.aaveLiquidator.flashLiquidate(
        env.tokens["USDC"], 
        Wei(flashLoanAmount * 1.2), 
        [currencyId, accounts[0].address, mock.address, False, redeemParams], 
        {"from": env.aaveLiquidator.owner()}
    )

    # 0.02 == liquidation discount
    expectedProfit = valuationFix + underlyingRedeemed * 0.02
    assert pytest.approx(env.tokens["USDC"].balanceOf(env.aaveLiquidator.owner()) - usdcBefore, rel=5e-2) == expectedProfit