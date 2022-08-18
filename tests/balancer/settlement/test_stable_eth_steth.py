
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
    get_redeem_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_normal_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH

def test_normal_single_maturity_incremental_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH

def test_post_maturity_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH

def test_emergency_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    primaryAmountBefore = accounts[0].balance()
    strategyContext = vault.getStrategyContext()
    settings = dict(strategyContext["baseStrategy"]["vaultSettings"].dict())
    settings["maxBalancerPoolShare"] = 0
    vault.setStrategyVaultSettings(
        list(settings.values()), 
        {"from": env.notional.owner()}
    )
    spotBalances = mock.getSpotBalances(strategyContext["baseStrategy"]["totalBPTHeld"])
    redeemParams = get_redeem_params(
        spotBalances["primaryBalance"] * 0.98, 
        spotBalances["secondaryBalance"] * 0.98, 
        get_dynamic_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )
    )
    vault.settleVaultEmergency(
        maturity,
        redeemParams,
        {"from": env.notional.owner()}
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
    assert pytest.approx(vaultState["totalAssetCash"], rel=1e-2) == 74512960552
