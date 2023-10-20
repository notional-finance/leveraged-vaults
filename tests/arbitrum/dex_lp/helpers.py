import math
import pytest
from brownie import Wei, interface
from brownie.network.state import Chain
from scripts.common import (
    get_deposit_params, 
    get_all_past_maturities,
    get_all_active_maturities,
    get_remaining_strategy_tokens
)

chain = Chain()

def get_metastable_amounts(poolContext, amount):
    primaryBalance = poolContext["basePool"]["primaryBalance"]
    secondaryBalance = poolContext["basePool"]["secondaryBalance"]
    primaryRatio = primaryBalance / (primaryBalance + secondaryBalance)
    primaryAmount = amount * primaryRatio
    secondaryAmount = amount - primaryAmount
    return (Wei(primaryAmount), Wei(secondaryAmount))

def get_expected_borrow_amount(env, currencyId, maturity, primaryBorrowAmount):
    expectedBorrowAmount = env.notional.getPrincipalFromfCashBorrow(
        currencyId, primaryBorrowAmount, maturity, 0, chain.time()
    )["borrowAmountUnderlying"]
    return expectedBorrowAmount

def enterMaturity(
    env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, account, callStatic=False, depositParams=None
):
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

def exitVaultPercent(env, vault, account, percent, redeemParams, callStatic=False):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    vaultShares = vaultAccount["vaultShares"]
    primaryBorrowAmount = vaultAccount["accountDebtUnderlying"]
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

def snapshot_invariants(env, vault, currencyId):
    activeMaturities = get_all_active_maturities(env.notional, currencyId)
    pastMaturities = get_all_past_maturities(env.notional, currencyId)
    vaultTotalfCash = 0
    vaultTotalVaultShares = 0
    for maturity in pastMaturities:
        vaultState = env.notional.getVaultState(vault.address, maturity)
        vaultTotalfCash += vaultState["totalDebtUnderlying"]
        vaultTotalVaultShares += vaultState["totalVaultShares"]
    for maturity in activeMaturities:
        vaultState = env.notional.getVaultState(vault.address, maturity)
        vaultTotalfCash += vaultState["totalDebtUnderlying"]
        vaultTotalVaultShares += vaultState["totalVaultShares"]
    rewardPool = interface.IRewardPool(vault.getStrategyContext()["stakingContext"]["rewardPool"])
    poolBalance = math.floor(rewardPool.balanceOf(vault.address) / 1e10)
    return {
        "totalDebtUnderlying": vaultTotalfCash,
        "totalVaultShares": vaultTotalVaultShares,
        "poolBalance": poolBalance
    }
    
def check_invariants(env, vault, accounts, currencyId, snapshot=None):
    rewardPool = interface.IRewardPool(vault.getStrategyContext()["stakingContext"]["rewardPool"])
    current = snapshot_invariants(env, vault, currencyId)
    accountTotalfCash = 0
    accountTotalVaultShares = 0
    for account in accounts:
        vaultAccount = env.notional.getVaultAccount(account, vault.address)
        accountTotalfCash += vaultAccount["accountDebtUnderlying"]
        accountTotalVaultShares += vaultAccount["vaultShares"]
    vaultTotalfCash = 0
    vaultTotalVaultShares = 0
    poolBalance = 0
    if snapshot != None:
        vaultTotalfCash = current["totalDebtUnderlying"] - snapshot["totalDebtUnderlying"]
        vaultTotalVaultShares = current["totalVaultShares"] - snapshot["totalVaultShares"]
        poolBalance = current["poolBalance"] - snapshot["poolBalance"]
    # Rounding error
    assert pytest.approx(vaultTotalfCash, abs=1) == accountTotalfCash
    assert vaultTotalVaultShares == accountTotalVaultShares
    # Rounding error
    if poolBalance > 1 and vaultTotalVaultShares > 0:
        assert pytest.approx(vault.convertStrategyTokensToPoolClaim(vaultTotalVaultShares) / 1e10, rel=1e-5) == poolBalance
    assert vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"] == rewardPool.balanceOf(vault)
    assert vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalVaultSharesGlobal"] == current["totalVaultShares"]

def check_account(env, vault, account, vaultShares, fCash):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    assert vaultAccount["vaultShares"] == vaultShares
    assert vaultAccount['accountDebtUnderlying'] == -fCash

def get_expected_pool_claim_amount(context, depositAmount, expectedBorrowAmount, primaryPercent=1, tradeFunc=None):
    env = context.env
    vault = context.mock
    totalJoinAmount = depositAmount + expectedBorrowAmount
    primaryAmount = totalJoinAmount * primaryPercent
    primaryAmountToSell = totalJoinAmount - primaryAmount
    undoCount = 0
    if primaryAmount > 0:
        context.transfer(vault, depositAmount + expectedBorrowAmount)
        undoCount += 1
    secondaryAmount = 0
    if primaryAmountToSell > 0:
        context.transfer(env.tradingModule, primaryAmountToSell)
        undoCount += 1
        res = tradeFunc(env, vault, primaryAmountToSell)
        secondaryAmount = res[0]
        undoCount += res[1]
    expectedPoolClaimAmount = vault.joinPoolAndStake.call([secondaryAmount, primaryAmount, 0], 0)
    if undoCount > 0:
        chain.undo(undoCount)
    return expectedPoolClaimAmount

# Deposit Op: [depositAmount, primaryBorrowAmount, depositor, maturity, depositParams, depositTrade]
def get_deposit_op(
    depositAmount, primaryBorrowAmount, depositor, maturityIndex=0, depositParams=None, primaryPercent=1, depositTradeFunc=None
):
    return [depositAmount, primaryBorrowAmount, depositor, maturityIndex, depositParams, primaryPercent, depositTradeFunc]
