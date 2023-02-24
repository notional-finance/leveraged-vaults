import pytest
import brownie
from brownie import Wei, accounts, MockBalancerCallback
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

def test_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
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
    primaryAmount, secondaryAmount = get_metastable_amounts(mock.getStrategyContext()["poolContext"], underlyingRedeemed)
    # discount primary and secondary slightly
    redeemParams = get_redeem_params(primaryAmount * 0.98, secondaryAmount * 0.98, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes()
    ))
    assert env.tokens["WETH"].balanceOf(env.liquidator.owner()) == 0

    with brownie.reverts():
        env.liquidator.flashLiquidate.call(
            env.tokens["WETH"], 
            Wei(flashLoanAmount * 1.2), 
            [1, accounts[0].address, mock.address, False, redeemParams], 
            {"from": env.liquidator.owner()}
        )

    env.liquidator.flashLiquidate(
        env.tokens["WETH"], 
        Wei(flashLoanAmount * 1.2), 
        [1, accounts[0].address, mock.address, True, redeemParams], 
        {"from": env.liquidator.owner()}
    )

    # 0.02 == liquidation discount
    expectedProfit = valuationFix + underlyingRedeemed * 0.02
    assert pytest.approx(env.tokens["WETH"].balanceOf(env.liquidator.owner()), rel=5e-2) == expectedProfit

def test_callback_reentrancy(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 180e8
    depositAmount = 20e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, env.whales["ETH"])

    cb = MockBalancerCallback.deploy(
        env.notional, 
        vault.getStrategyContext()["poolContext"]["basePool"]["poolToken"],
        {"from": accounts[0]}
    )
    
    env.tokens["cETH"].transfer(cb.address, 100000e8, {"from": env.whales["cETH"]})
    env.tokens["wstETH"].transfer(cb.address, 1000e18, {"from": env.whales["wstETH"]})
    env.whales["ETH"].transfer(cb.address, 1000e18)
    env.tokens["cETH"].approve(env.notional, 2**256-1, {"from": env.whales["cETH"]})
    env.tokens["cETH"].approve(env.notional, 2**256-1, {"from": cb})
    
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    callParams = [env.whales["ETH"], vault.address, redeemParams]

    with brownie.reverts():
        cb.deleverage.call(
            1000e18,
            1000e18,
            callParams,
            {"from": accounts[0]}
        )
