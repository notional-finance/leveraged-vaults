
import math
import pytest
import brownie
from brownie import accounts, Wei
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
    currencyId = 1
    primaryBorrowAmount = 300e8
    depositAmount = 100e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, accounts[0])
    settlementWindow = vault.getStrategyContext()["baseStrategy"]["settlementPeriodInSeconds"]
    chain.sleep(maturity - settlementWindow + 1 - chain.time())
    chain.mine(5)
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})
    redeemParams = get_redeem_params(
        0, 0, get_dynamic_trade_params(DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(100e18), True, bytes(0))
    )
    tokensToRedeem = math.floor(env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"] * 0.5)

    # Can't settle without the proper role
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    # Only Notional owner can grant roles
    with brownie.reverts():
        vault.grantRole.call(vault.getRoles()["normalSettlement"], accounts[1], {"from": accounts[2]})
    vault.grantRole(vault.getRoles()["normalSettlement"], accounts[1], {"from": env.notional.owner()})

    # Test settlement (settle half)
    vaultState = env.notional.getVaultState(vault.address, maturity)
    underlyingCashBefore = vault.convertStrategyToUnderlying(accounts[0], vaultState["totalStrategyTokens"], maturity)
    vault.settleVaultNormal(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    totalUnderlyingCash = convert_to_underlying(env, currencyId, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore / 2
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem

    # Can't deposit during settlement (totalAssetCash > 0)
    with brownie.reverts():
        enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[1], True)

    # Redeem is allowed
    redeemParams2 = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, bytes(0)
    ))
    exitVaultPercent(env, vault, accounts[0], 1.0, redeemParams2)
    chain.undo()

    tokensToRedeem = env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"]

    # Settlement cool down
    with brownie.reverts():
         vault.settleVaultNormal.call(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    chain.sleep(3600 * 10)
    chain.mine(5)    

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

    # Complete settlement
    vault.settleVaultNormal(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
    assert vaultState["isSettled"] == False
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore

def test_post_maturity_single_maturity(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 300e8
    depositAmount = 100e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, accounts[0])
    tokensToRedeem = math.floor(env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"] * 0.5)
    redeemParams = get_redeem_params(
        0, 0, get_dynamic_trade_params(DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(100e18), True, bytes(0))
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

    vaultState = env.notional.getVaultState(vault.address, maturity)
    underlyingCashBefore = vault.convertStrategyToUnderlying(accounts[0], vaultState["totalStrategyTokens"], maturity)

    vault.settleVaultPostMaturity(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

    vaultState = env.notional.getVaultState(vault.address, maturity)
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore / 2
    assert vaultState["totalStrategyTokens"] == vaultState["totalVaultShares"] - tokensToRedeem
    assert vaultState["isSettled"] == False

    tokensToRedeem = env.notional.getVaultState(vault.address, maturity)["totalStrategyTokens"]

    # Complete settlement
    vault.settleVaultPostMaturity(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
    assert vaultState["isSettled"] == True
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore

def test_emergency_single_maturity(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    currencyId = 1
    primaryBorrowAmount = 300e8
    depositAmount = 100e18
    maturity = env.notional.getActiveMarkets(currencyId)[0][1]
    enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, accounts[0])
    redeemParams = get_redeem_params(
        0, 0, get_dynamic_trade_params(DEX_ID["CURVE"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(100e18), True, bytes(0))
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

    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vault.getEmergencySettlementBPTAmount(maturity) == vault.convertStrategyTokensToBPTClaim(vaultState["totalStrategyTokens"])
    underlyingCashBefore = vault.convertStrategyToUnderlying(accounts[0], vaultState["totalStrategyTokens"], maturity)

    vault.settleVaultEmergency(maturity, redeemParams, {"from": accounts[1]})

    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] <= 1 # Rounding error?
    totalUnderlyingCash = convert_to_underlying(env, 1, vaultState["totalAssetCash"])
    assert pytest.approx(totalUnderlyingCash, rel=1e-2) == underlyingCashBefore
