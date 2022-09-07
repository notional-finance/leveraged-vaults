import pytest
import brownie
from brownie import accounts
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, check_invariant
from scripts.common import get_updated_vault_settings

def test_single_maturity_low_leverage_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    vaultAccount = env.notional.getVaultAccount(env.whales["USDC"], vault.address)
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 1477703500011
    underlyingValue = vault.convertStrategyToUnderlying(env.whales["USDC"], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e-2
    check_invariant(env, vault, [env.whales["USDC"]], [maturity])

def test_single_maturity_high_leverage_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 40000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    vaultAccount = env.notional.getVaultAccount(env.whales["USDC"], vault.address)
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 4919438138917
    underlyingValue = vault.convertStrategyToUnderlying(env.whales["USDC"], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e-2
    check_invariant(env, vault, [env.whales["USDC"]], [maturity])

def test_leverage_ratio_too_high_failure(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 60000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"], True)

def test_balancer_share_too_high_failure(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
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
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    with brownie.reverts():
        enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"], True)
