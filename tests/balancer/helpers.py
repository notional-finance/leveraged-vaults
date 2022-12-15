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
    set_dex_flags
)

chain = Chain()

def get_metastable_amounts(poolContext, amount):
    primaryBalance = poolContext["primaryBalance"]
    secondaryBalance = poolContext["secondaryBalance"]
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

def snapshot_invariants(env, vault, maturities):
    vaultTotalfCash = 0
    vaultTotalVaultShares = 0
    vaultTotalStrategyTokens = 0
    for maturity in maturities:
        vaultState = env.notional.getVaultState(vault.address, maturity)
        vaultTotalfCash += vaultState["totalfCash"]
        vaultTotalVaultShares += vaultState["totalVaultShares"]
        vaultTotalStrategyTokens += vaultState["totalStrategyTokens"]
    auraPool = interface.IAuraRewardPool(vault.getStrategyContext()["stakingContext"]["auraRewardPool"])
    auraBalance = math.floor(auraPool.balanceOf(vault.address) / 1e10)
    return {
        "totalfCash": vaultTotalfCash,
        "totalVaultShares": vaultTotalVaultShares,
        "totalStrategyTokens": vaultTotalStrategyTokens,
        "auraBalance": auraBalance
    }
    
def check_invariants(env, vault, accounts, maturities, snapshot=None):
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
    auraPool = interface.IAuraRewardPool(vault.getStrategyContext()["stakingContext"]["auraRewardPool"])
    auraBalance = math.floor(auraPool.balanceOf(vault.address) / 1e10)
    if snapshot != None:
        vaultTotalfCash -= snapshot["totalfCash"]
        vaultTotalVaultShares -= snapshot["totalVaultShares"]
        vaultTotalStrategyTokens -= snapshot["totalStrategyTokens"]
        auraBalance -= snapshot["auraBalance"]
    assert vaultTotalfCash == accountTotalfCash
    assert vaultTotalVaultShares == accountTotalVaultShares
    # Rounding error
    if auraBalance > 1:
        assert pytest.approx(vault.convertStrategyTokensToBPTClaim(vaultTotalStrategyTokens) / 1e10, rel=1e-5) == auraBalance
    assert vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalBPTHeld"] == auraPool.balanceOf(vault)
    if snapshot != None:
        vaultTotalStrategyTokens += snapshot["totalStrategyTokens"]
    assert vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalStrategyTokenGlobal"] == vaultTotalStrategyTokens

def check_account(env, vault, account, vaultShares, fCash):
    vaultAccount = env.notional.getVaultAccount(account, vault.address)
    assert vaultAccount["vaultShares"] == vaultShares
    assert vaultAccount['fCash'] == -fCash

def get_expected_bpt_amount(context, depositAmount, expectedBorrowAmount, primaryPercent=1):
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
        env.whales["ETH"].transfer(env.tradingModule, primaryAmountToSell)
        env.tradingModule.setTokenPermissions(
            env.tradingModule, 
            ZERO_ADDRESS, 
            [True, set_dex_flags(0, BALANCER_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
            {"from": env.notional.owner()})
        trade = [
            TRADE_TYPE["EXACT_IN_SINGLE"], 
            ZERO_ADDRESS,
            env.tokens["wstETH"].address, 
            primaryAmountToSell, 
            0, 
            chain.time() + 20000, 
            eth_abi.encode_abi(
                ["(bytes32)"],
                [[to_bytes("0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080", "bytes32")]]
            )
        ]
        env.tradingModule.executeTrade(DEX_ID["BALANCER_V2"], trade, {"from": env.whales["ETH"]})
        secondaryAmount = env.tokens["wstETH"].balanceOf(env.tradingModule)
        env.tokens["wstETH"].transfer(vault, secondaryAmount, {"from": env.tradingModule})
        undoCount += 4
    expectedBPTAmount = vault.joinPoolAndStake.call(primaryAmount, secondaryAmount, 0)
    if undoCount > 0:
        chain.undo(undoCount)
    return expectedBPTAmount
