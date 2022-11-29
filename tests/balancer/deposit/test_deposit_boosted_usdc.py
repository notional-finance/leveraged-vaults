from tests.fixtures import *
from tests.balancer.acceptance import (
    USDCPrimaryContext, 
    deposit_test, 
    negative_test_leverage_ratio_too_high
)

def test_single_maturity_low_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit_test(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 5000e8)

def test_single_maturity_high_leverage_success(StratBoostedPoolUSDCPrimary):
    deposit_test(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 40000e8)

def test_leverage_ratio_too_high_failure(StratBoostedPoolUSDCPrimary):
    negative_test_leverage_ratio_too_high(USDCPrimaryContext(*StratBoostedPoolUSDCPrimary), 10000e6, 60000e8)

@pytest.mark.skip
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
