import math
import eth_abi
import pytest
from brownie import ZERO_ADDRESS, Wei, interface
from brownie.convert import to_bytes
from brownie.network.state import Chain
from scripts.common import (
    TRADE_TYPE,
    DEX_ID,
    get_deposit_params, 
    set_trade_type_flags, 
    set_dex_flags,
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

def convert_to_underlying(env, currencyId, assetCash, underlyingPrecision):
    assetRate = env.notional.getCurrencyAndRates(currencyId)["assetRate"]
    return (assetCash * assetRate["rate"] / 1e10 / assetRate["underlyingDecimals"]) * underlyingPrecision / 1e8

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

def snapshot_invariants(env, vault, currencyId):
    activeMaturities = get_all_active_maturities(env.notional, currencyId)
    pastMaturities = get_all_past_maturities(env.notional, currencyId)
    vaultTotalfCash = 0
    vaultTotalVaultShares = 0
    data = get_remaining_strategy_tokens(vault.address)
    vaultTotalStrategyTokens = data["amount"]
    for maturity in pastMaturities:
        vaultState = env.notional.getVaultState(vault.address, maturity)
        vaultTotalfCash += vaultState["totalfCash"]
        vaultTotalVaultShares += vaultState["totalVaultShares"]
        if maturity not in data["maturities"]:
            vaultTotalStrategyTokens += vaultState["totalStrategyTokens"]        
    for maturity in activeMaturities:
        vaultState = env.notional.getVaultState(vault.address, maturity)
        vaultTotalfCash += vaultState["totalfCash"]
        vaultTotalVaultShares += vaultState["totalVaultShares"]
        vaultTotalStrategyTokens += vaultState["totalStrategyTokens"]
    rewardPool = interface.IRewardPool(vault.getStrategyContext()["stakingContext"]["rewardPool"])
    poolBalance = math.floor(rewardPool.balanceOf(vault.address) / 1e10)
    return {
        "totalfCash": vaultTotalfCash,
        "totalVaultShares": vaultTotalVaultShares,
        "totalStrategyTokens": vaultTotalStrategyTokens,
        "poolBalance": poolBalance
    }
    
def check_invariants(env, vault, accounts, currencyId, snapshot=None):
    rewardPool = interface.IRewardPool(vault.getStrategyContext()["stakingContext"]["rewardPool"])
    current = snapshot_invariants(env, vault, currencyId)
    accountTotalfCash = 0
    accountTotalVaultShares = 0
    for account in accounts:
        vaultAccount = env.notional.getVaultAccount(account, vault.address)
        accountTotalfCash += vaultAccount["fCash"]
        accountTotalVaultShares += vaultAccount["vaultShares"]
    vaultTotalfCash = 0
    vaultTotalVaultShares = 0
    vaultTotalStrategyTokens = 0
    poolBalance = 0
    if snapshot != None:
        vaultTotalfCash = current["totalfCash"] - snapshot["totalfCash"]
        vaultTotalVaultShares = current["totalVaultShares"] - snapshot["totalVaultShares"]
        vaultTotalStrategyTokens = current["totalStrategyTokens"] - snapshot["totalStrategyTokens"]
        poolBalance = current["poolBalance"] - snapshot["poolBalance"]
    assert vaultTotalfCash == accountTotalfCash
    assert vaultTotalVaultShares == accountTotalVaultShares
    # Rounding error
    if poolBalance > 1 and vaultTotalStrategyTokens > 0:
        assert pytest.approx(vault.convertStrategyTokensToPoolClaim(vaultTotalStrategyTokens) / 1e10, rel=1e-5) == poolBalance
    assert vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"] == rewardPool.balanceOf(vault)
    assert vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalStrategyTokenGlobal"] == current["totalStrategyTokens"]

def check_account(env, vault, account, vaultShares, fCash):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    assert vaultAccount["vaultShares"] == vaultShares
    assert vaultAccount['fCash'] == -fCash

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
    expectedPoolClaimAmount = vault.joinPoolAndStake.call(primaryAmount, secondaryAmount, 0)
    if undoCount > 0:
        chain.undo(undoCount)
    return expectedPoolClaimAmount

# Deposit Op: [depositAmount, primaryBorrowAmount, depositor, maturity, depositParams, depositTrade]
def get_deposit_op(
    depositAmount, primaryBorrowAmount, depositor, maturityIndex=0, depositParams=None, primaryPercent=1, depositTradeFunc=None
):
    return [depositAmount, primaryBorrowAmount, depositor, maturityIndex, depositParams, primaryPercent, depositTradeFunc]
