import pytest
import brownie
from brownie import accounts
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, get_expected_bpt_amount, snapshot_invariants, check_invariants
from tests.balancer.acceptance import DAIPrimaryContext, deposit_tests
from scripts.common import get_updated_vault_settings

def test_acceptance(StratBoostedPoolDAIPrimary):
    deposit_tests(DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 10000e18, 5000e8)

@pytest.mark.skip
def test_single_maturity_high_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
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

@pytest.mark.skip
def test_leverage_ratio_too_high_failure(StratBoostedPoolDAIPrimary):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 60000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"], True)

@pytest.mark.skip
def test_balancer_share_too_high_failure(StratBoostedPoolDAIPrimary):
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

