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
    env, 
    vault, 
    currencyId, 
    maturityIndex, 
    depositAmount, 
    primaryBorrowAmount, 
    account,
    depositParams=None
):
    maturity = env.notional.getActiveMarkets(currencyId)[maturityIndex][1]
    value = 0
    if currencyId == 1:
        value = depositAmount
    if depositParams == None:
        depositParams = get_deposit_params()
    env.notional.enterVault(
        account,
        vault.address,
        depositAmount,
        maturity,
        primaryBorrowAmount,
        0,
        depositParams,
        {"from": account, "value": value}
    )
    return maturity

def exitVaultPercent(env, vault, account, percent, redeemParams):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    vaultShares = vaultAccount["vaultShares"]
    primaryBorrowAmount = vaultAccount["fCash"]
    env.notional.exitVault(
        account,
        vault.address,
        account,
        vaultShares * percent,
        -primaryBorrowAmount * percent,
        0,
        redeemParams,
        {"from": account}
    )
