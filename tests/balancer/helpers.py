import math
from brownie import Wei
from scripts.common import (
    get_deposit_params, 
)

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

def exitVaultPercent(env, vault, account, percent, redeemParams):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    vaultShares = vaultAccount["vaultShares"]
    primaryBorrowAmount = vaultAccount["fCash"]
    sharesToRedeem = math.floor(vaultShares * percent)
    fCashToRepay = math.floor(-primaryBorrowAmount * percent)
    env.notional.exitVault(
        account,
        vault.address,
        account,
        sharesToRedeem,
        fCashToRepay,
        0,
        redeemParams,
        {"from": account}
    )
    return (sharesToRedeem, fCashToRepay)
