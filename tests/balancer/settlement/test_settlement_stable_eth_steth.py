
import math
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
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    chain.sleep(maturity - 3600 * 24 * 6 - chain.time())
    chain.mine()
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})
    redeemParams = get_redeem_params(0, 0, 
        get_dynamic_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalAssetCash"] == 0
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"]
    tokensToRedeem = math.floor(vaultState["totalStrategyTokens"] * 0.5)
    vault.settleVaultNormal(
        maturity,
        tokensToRedeem,
        redeemParams,
        {"from": accounts[1]}
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert pytest.approx(vaultState["totalAssetCash"], rel=1e-2) == 37256494853
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem

    # Can't deposit during settlement (totalAssetCash > 0)
    with brownie.reverts():
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[1], True)


def test_post_maturity_single_maturity_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalAssetCash"] == 0
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"]
    tokensToRedeem = math.floor(vaultState["totalStrategyTokens"] * 0.5)
    redeemParams = get_redeem_params(0, 0, 
        get_dynamic_trade_params(
            DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
        )
    )

    # Can't call settleVaultPostMaturity before maturity
    with brownie.reverts():
        vault.settleVaultPostMaturity.call(maturity, tokensToRedeem, redeemParams, {"from": env.notional.owner()})

    chain.sleep(maturity + 3600 * 24 - chain.time())
    chain.mine()
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})

    # Can't call settleVaultPostNormal after maturity
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    # settleVaultPostMaturity is authenticated
    with brownie.reverts():
        vault.settleVaultPostMaturity.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    vault.settleVaultPostMaturity(maturity, tokensToRedeem, redeemParams, {"from": env.notional.owner()})

    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert pytest.approx(vaultState["totalAssetCash"], rel=1e-2) == 37256494853
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem

def test_emergency_single_maturity_success(StratStableETHstETH):
    (env, vault) = StratStableETHstETH
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
    redeemParams = get_redeem_params(0, 0, 
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
        