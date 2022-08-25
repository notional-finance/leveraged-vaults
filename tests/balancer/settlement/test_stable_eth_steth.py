
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
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    chain.sleep(maturity - 3600 * 24 * 6 - chain.time())
    chain.mine()
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})
    strategyContext = vault.getStrategyContext()
    spotBalances = mock.getSpotBalances(strategyContext["baseStrategy"]["totalBPTHeld"])
    redeemParams = get_redeem_params(
        spotBalances["primaryBalance"] * 0.5 * 0.98, 
        spotBalances["secondaryBalance"] * 0.5 * 0.98, 
        get_dynamic_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalAssetCash"] == 0
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"]
    vault.settleVaultNormal(
        maturity,
        vaultState["totalStrategyTokens"] * 0.5,
        redeemParams,
        {"from": accounts[1]}
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert pytest.approx(vaultState["totalAssetCash"], rel=1e-2) == 37256494853
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] * 0.5

def test_post_maturity_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH

def test_emergency_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
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
        {"from": accounts[1]}
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
    assert pytest.approx(vaultState["totalAssetCash"], rel=1e-2) == 74512960552

def test_deposit_in_settlement_window_failure(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    primaryBorrowAmount = Wei(5e8)
    depositAmount = Wei(10e18)
    settlementPeriod = vault.getStrategyContext()["baseStrategy"]["settlementPeriodInSeconds"]
    sleepAmount = maturity - settlementPeriod + 1 - chain.time()
    chain.sleep(sleepAmount)
    chain.mine()
    with brownie.reverts():
        env.notional.enterVault.call(
            env.whales["ETH"],
            vault.address,
            depositAmount,
            maturity,
            primaryBorrowAmount,
            0,
            get_deposit_params(),
            {"from": env.whales["ETH"], "value": depositAmount}
        )
        