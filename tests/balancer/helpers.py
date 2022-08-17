from scripts.common import (
    get_deposit_params, 
)

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
