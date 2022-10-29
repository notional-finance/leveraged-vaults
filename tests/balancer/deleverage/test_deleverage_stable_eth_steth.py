import pytest
from brownie import Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, check_invariant, get_metastable_amounts
from scripts.common import (
    get_redeem_params, 
    get_dynamic_trade_params, 
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 40e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vault.setValuationFactor(accounts[0], 0.9e8, {"from": accounts[0]})
    collateralInfo = env.notional.getVaultAccountCollateralRatio(accounts[0], vault.address)

    # Should be undercollateralized
    assert collateralInfo["collateralRatio"] < collateralInfo["minCollateralRatio"]

    # Manipulation the valuation factor causes the vault to transfer extra tokens
    # to the liquidator. We keep track of this for the comparison at the end.
    vaultSharesToLiquidator = collateralInfo["vaultSharesToLiquidator"]
    valuationFixBefore = vault.convertStrategyToUnderlying(accounts[0], vaultSharesToLiquidator, maturity)
    vault.setValuationFactor(accounts[0], 1e8, {"from": accounts[0]})
    valuationFixAfter = vault.convertStrategyToUnderlying(accounts[0], vaultSharesToLiquidator, maturity)
    vault.setValuationFactor(accounts[0], 0.9e8, {"from": accounts[0]})
    valuationFix = valuationFixAfter - valuationFixBefore

    assetAmountFromLiquidator = collateralInfo["maxLiquidatorDepositAssetCash"]
    vaultState = env.notional.getVaultState(vault, maturity)
    assetRate = env.notional.getCurrencyAndRates(1)["assetRate"]
    strategyTokensToRedeem = vaultSharesToLiquidator / vaultState["totalVaultShares"] * vaultState["totalStrategyTokens"]
    underlyingRedeemed = vault.convertStrategyToUnderlying(accounts[0], strategyTokensToRedeem, maturity)
    flashLoanAmount = assetRate["rate"] * assetAmountFromLiquidator / assetRate["underlyingDecimals"]
    primaryAmount, secondaryAmount = get_metastable_amounts(vault.getStrategyContext()["poolContext"], underlyingRedeemed)
    # discount primary and secondary slightly
    redeemParams = get_redeem_params(primaryAmount * 0.98, secondaryAmount * 0.98, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    assert env.tokens["WETH"].balanceOf(env.liquidator.owner()) == 0
    env.liquidator.flashLiquidate(
        env.tokens["WETH"], 
        Wei(flashLoanAmount * 1.2), 
        [1, accounts[0].address, vault.address, redeemParams], 
        {"from": env.liquidator.owner()}
    )

    # 0.04 == liquidation discount
    expectedProfit = valuationFix + underlyingRedeemed * 0.04
    assert pytest.approx(env.tokens["WETH"].balanceOf(env.liquidator.owner()), rel=1e-2) == expectedProfit
