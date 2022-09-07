import math
import pytest
from brownie import Wei, interface
from scripts.common import get_deposit_params

def get_metastable_amounts(poolContext, amount):
    primaryBalance = poolContext["primaryBalance"]
    secondaryBalance = poolContext["secondaryBalance"]
    primaryRatio = primaryBalance / (primaryBalance + secondaryBalance)
    primaryAmount = amount * primaryRatio
    secondaryAmount = amount - primaryAmount
    return (Wei(primaryAmount), Wei(secondaryAmount))

def enterMaturity(
    env, vault, currencyId, maturityIndex, depositAmount, primaryBorrowAmount, account, callStatic=False, depositParams=None
):
    maturity = env.notional.getActiveMarkets(currencyId)[maturityIndex][1]
    value = 0
    if currencyId == 1:
        value = depositAmount
    if depositParams == None:
        depositParams = get_deposit_params()
    if callStatic:
        env.notional.enterVault.call(
            account,
            vault.address,
            Wei(depositAmount),
            Wei(maturity),
            Wei(primaryBorrowAmount),
            0,
            depositParams,
            {"from": account, "value": Wei(value)}
        )
    else:
        env.notional.enterVault(
            account,
            vault.address,
            Wei(depositAmount),
            Wei(maturity),
            Wei(primaryBorrowAmount),
            0,
            depositParams,
            {"from": account, "value": Wei(value)}
        )
    return maturity

def exitVaultPercent(env, vault, account, percent, redeemParams, callStatic=False):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    vaultShares = vaultAccount["vaultShares"]
    primaryBorrowAmount = vaultAccount["fCash"]
    sharesToRedeem = math.floor(vaultShares * percent)
    fCashToRepay = math.floor(-primaryBorrowAmount * percent)
    if callStatic:
        env.notional.exitVault.call(
            account, vault.address, account, sharesToRedeem, fCashToRepay, 0, redeemParams, {"from": account}
        )
    else:
        env.notional.exitVault(
            account, vault.address, account, sharesToRedeem, fCashToRepay, 0, redeemParams, {"from": account}
        )
    return (sharesToRedeem, fCashToRepay)

def check_invariant(env, vault, accounts, maturities):
    accountTotalfCash = 0
    accountTotalVaultShares = 0
    for account in accounts:
        vaultAccount = env.notional.getVaultAccount(account, vault.address)
        accountTotalfCash += vaultAccount["fCash"]
        accountTotalVaultShares += vaultAccount["vaultShares"]
    vaultTotalfCash = 0
    vaultTotalVaultShares = 0
    vaultTotalStrategyTokens = 0
    for maturity in maturities:
        vaultState = env.notional.getVaultState(vault.address, maturity)
        vaultTotalfCash += vaultState["totalfCash"]
        vaultTotalVaultShares += vaultState["totalVaultShares"]
        vaultTotalStrategyTokens += vaultState["totalStrategyTokens"]
    assert vaultTotalfCash == accountTotalfCash
    assert vaultTotalVaultShares == accountTotalVaultShares
    auraPool = interface.IAuraRewardPool(vault.getStrategyContext()["stakingContext"]["auraRewardPool"])
    assert pytest.approx(vaultTotalStrategyTokens, rel=1e-6) == math.floor(auraPool.balanceOf(vault.address) / 1e10)

def check_account(env, vault, account, vaultShares, fCash):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    assert vaultAccount["vaultShares"] == vaultShares
    assert vaultAccount['fCash'] == -fCash
