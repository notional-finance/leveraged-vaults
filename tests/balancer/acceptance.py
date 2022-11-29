import pytest
import brownie
from brownie import ZERO_ADDRESS, accounts
from tests.balancer.helpers import (
    snapshot_invariants, 
    check_invariants, 
    enterMaturity, 
    exitVaultPercent,
    get_expected_bpt_amount,
    get_expected_borrow_amount
)

class ETHPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 1
        self.token = ZERO_ADDRESS
        self.depositor = accounts[0]
        self.primaryDecimals = 18
    def transfer(self, dest, amount):
        self.depositor.transfer(dest, amount)

class DAIPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 2
        self.token = env.tokens["DAI"]
        self.depositor = env.whales["DAI_EOA"]
        self.token.approve(self.env.notional, 2**256-1, {"from": self.depositor})
        self.primaryDecimals = self.token.decimals()
    def transfer(self, dest, amount):
        self.token.transfer(dest, amount, {"from": self.depositor})

class USDCPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 3
        self.token = env.tokens["USDC"]
        self.depositor = env.whales["USDC"]
        self.token.approve(self.env.notional, 2**256-1, {"from": self.depositor})
        self.primaryDecimals = self.token.decimals()
    def transfer(self, dest, amount):
        self.token.transfer(dest, amount, {"from": self.depositor})

def deposit_test(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals
    maturities = [m[1] for m in notional.getActiveMarkets(currencyId)]
    snapshot = snapshot_invariants(env, vault, maturities)
    expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturities[0], primaryBorrowAmount)
    expectedBptAmount = get_expected_bpt_amount(context, depositAmount, expectedBorrowAmount)
    enterMaturity(env, vault, currencyId, maturities[0], depositAmount, primaryBorrowAmount, depositor)
    vaultAccount = notional.getVaultAccount(depositor, vault.address)
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-3) == expectedBptAmount
    underlyingValue = vault.convertStrategyToUnderlying(depositor, vaultAccount["vaultShares"], maturities[0])
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * primaryPrecision / 1e8
    check_invariants(env, vault, [depositor], maturities, snapshot)

def redeem_test(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def normal_settlement_test(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def post_maturity_settlement_test(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def emergency_settlement_test(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def roll_test(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def negative_test_leverage_ratio_too_high(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    maturities = [m[1] for m in notional.getActiveMarkets(currencyId)]
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, currencyId, maturities[0], depositAmount, primaryBorrowAmount, depositor, True)

def negative_test_balancer_share_too_high(context):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    # Only Notional owner can change settings
    with brownie.reverts():
        vault.setStrategyVaultSettings.call(
            get_updated_vault_settings(settings, maxBalancerPoolShare=0),
            {"from": accounts[0]}
        )
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxBalancerPoolShare=0),
        {"from": env.notional.owner()}
    )
    primaryBorrowAmount = 60000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    with brownie.reverts():
        enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"], True)

