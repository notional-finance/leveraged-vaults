import pytest
import brownie
from brownie import accounts
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, check_invariant
from scripts.common import get_updated_vault_settings

def test_single_maturity_low_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    vaultAccount = env.notional.getVaultAccount(env.whales["DAI_EOA"], vault.address)
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 1477704605425
    underlyingValue = vault.convertStrategyToUnderlying(env.whales["DAI_EOA"], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10
    check_invariant(env, vault, [env.whales["DAI_EOA"]], [maturity])

def test_single_maturity_high_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 40000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    vaultAccount = env.notional.getVaultAccount(env.whales["DAI_EOA"], vault.address)
    assert vaultAccount["fCash"] == -primaryBorrowAmount
    assert pytest.approx(vaultAccount["vaultShares"], rel=1e-5) == 4919575575541
    underlyingValue = vault.convertStrategyToUnderlying(env.whales["DAI_EOA"], vaultAccount["vaultShares"], maturity)
    assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * 1e10
    check_invariant(env, vault, [env.whales["DAI_EOA"]], [maturity])

def test_leverage_ratio_too_high_failure(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 60000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"], True)

def test_balancer_share_too_high_failure(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
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

