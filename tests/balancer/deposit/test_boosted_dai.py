import pytest
import brownie
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import get_updated_vault_settings

def test_single_maturity_low_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])

def test_single_maturity_high_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 40000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])

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
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxBalancerPoolShare=0),
        {"from": env.notional.owner()}
    )
    primaryBorrowAmount = 60000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    with brownie.reverts():
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"], True)
