
import math
import pytest
import brownie
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import (
    enterMaturity, 
    exitVaultPercent, 
    get_expected_borrow_amount, 
    convert_to_underlying
)
from scripts.common import (
    get_updated_vault_settings, 
    get_dynamic_trade_params,
    get_redeem_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_normal_single_maturity(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    settlementWindow = vault.getStrategyContext()["baseStrategy"]["settlementPeriodInSeconds"]
    chain.sleep(maturity - settlementWindow + 1 - chain.time())
    chain.mine(5)
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})
    redeemParams = get_redeem_params(
        0, 0, get_dynamic_trade_params(DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0))
    )
    tokensToRedeem = math.floor(env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"] * 0.5)

    # Can't settle without the proper role
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["normalSettlement"], accounts[1], {"from": accounts[2]})
    vault.grantRole(vault.getRoles()["normalSettlement"], accounts[1], {"from": env.notional.owner()})

    # Can't settle with bad slippage setting
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, get_redeem_params(
            0, 0, get_dynamic_trade_params(DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 10e6, True, bytes(0))
        ), {"from": accounts[1]})

    # Can't redeem beyond maxUnderlyingSurplus
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    oldMaxUnderlyingSurplus = settings["maxUnderlyingSurplus"]
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxUnderlyingSurplus=0), {"from": env.notional.owner()}
    )
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxUnderlyingSurplus=oldMaxUnderlyingSurplus), {"from": env.notional.owner()}
    )

    # Test settlement (settle half)
    vault.settleVaultNormal(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == (depositAmount + expectedBorrowAmount) / 2
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem

    # Can't deposit during settlement (totalAssetCash > 0)
    with brownie.reverts():
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[1], True)

    # Redeem is allowed
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    exitVaultPercent(env, vault, accounts[0], 1.0, redeemParams)
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalAssetCash"] == 0
    assert vaultState["totalStrategyTokens"] == 0
    assert vaultState["totalVaultShares"] == 0
    assert vaultState["totalfCash"] == 0
    chain.undo()

    tokensToRedeem = env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"]

    # Settlement cool down
    with brownie.reverts():
         vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    chain.sleep(3600 * 10)
    chain.mine(5)    

    # Complete settlement
    vault.settleVaultNormal(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
    assert vaultState["isSettled"] == False
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == depositAmount + expectedBorrowAmount

def test_post_maturity_single_maturity(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    tokensToRedeem = math.floor(env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"] * 0.5)
    redeemParams = get_redeem_params(
        0, 0, get_dynamic_trade_params(DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0))
    )

    # Can't call settleVaultPostMaturity before maturity
    with brownie.reverts():
        vault.settleVaultPostMaturity.call(maturity, tokensToRedeem, redeemParams, {"from": env.notional.owner()})

    chain.sleep(maturity + 1 - chain.time())
    chain.mine(5)
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})

    # Can't call settleVaultPostNormal after maturity
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    # settleVaultPostMaturity is authenticated
    with brownie.reverts():
        vault.settleVaultPostMaturity.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["postMaturitySettlement"], accounts[1], {"from": accounts[2]})
    vault.grantRole(vault.getRoles()["postMaturitySettlement"], accounts[1], {"from": env.notional.owner()})

    vault.settleVaultPostMaturity(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    vaultState = env.notional.getVaultState(vault.address, maturity)
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == (depositAmount + expectedBorrowAmount) / 2
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem
    assert vaultState["isSettled"] == True

def test_emergency_single_maturity(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    expectedBorrowAmount = get_expected_borrow_amount(env, 1, 0, primaryBorrowAmount)
    maturity = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    redeemParams = get_redeem_params(
        0, 0, get_dynamic_trade_params(DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0))
    )

    # Role check
    with brownie.reverts():
        vault.settleVaultEmergency.call(maturity, redeemParams, {"from": accounts[1]})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["emergencySettlement"], accounts[1], {"from": accounts[2]})
    vault.grantRole(vault.getRoles()["emergencySettlement"], accounts[1], {"from": env.notional.owner()})

    # Cannot get emergency settlement amount if we are below the threshold
    with brownie.reverts():
        vault.getEmergencySettlementBPTAmount(maturity)

    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    vault.setStrategyVaultSettings(get_updated_vault_settings(settings, maxBalancerPoolShare=0), {"from": env.notional.owner()})

    assert vault.getEmergencySettlementBPTAmount(maturity) == vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalBPTHeld"]

    vault.settleVaultEmergency(maturity, redeemParams, {"from": accounts[1]})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == depositAmount + expectedBorrowAmount
