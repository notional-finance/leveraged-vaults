from scripts.common import (
    get_deposit_params, 
)

def enterMaturity(env, vault, currencyId, maturityIndex, depositAmount, primaryBorrowAmount, account):
    maturity = env.notional.getActiveMarkets(currencyId)[maturityIndex][1]
    value = 0
    if currencyId == 1:
        value = depositAmount
    env.notional.enterVault(
        account,
        vault.address,
        depositAmount,
        maturity,
        primaryBorrowAmount,
        0,
        get_deposit_params(),
        {"from": account, "value": value}
    )
    return maturity
