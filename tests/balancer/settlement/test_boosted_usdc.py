
import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import (
    get_deposit_params, 
    get_dynamic_trade_params,
    get_univ3_single_data,
    get_redeem_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_normal_single_maturity_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    chain.sleep(maturity - 3600 * 24 * 6 - chain.time())
    chain.mine()
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})
    redeemParams = get_redeem_params(
        0, # minPrimary is calculated internally for boosted pools 
        0, 
        get_dynamic_trade_params(
            DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
        )
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    vault.settleVaultNormal(
        maturity,
        vaultState["totalStrategyTokens"] * 0.5,
        redeemParams,
        {"from": accounts[1]}
    )

def test_post_maturity_single_maturity_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary

def test_emergency_single_maturity_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    strategyContext = vault.getStrategyContext()
    settings = dict(strategyContext["baseStrategy"]["vaultSettings"].dict())
    settings["maxBalancerPoolShare"] = 0
    vault.setStrategyVaultSettings(
        list(settings.values()), 
        {"from": env.notional.owner()}
    )
    redeemParams = get_redeem_params(
        0, # minPrimary is calculated internally for boosted pools 
        0, 
        get_dynamic_trade_params(
            DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
        )
    )
    vault.settleVaultEmergency(
        maturity,
        redeemParams,
        {"from": env.notional.owner()}
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
