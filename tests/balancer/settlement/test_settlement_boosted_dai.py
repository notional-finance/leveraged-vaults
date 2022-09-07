
import math
import brownie
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity
from scripts.common import (
    get_dynamic_trade_params,
    get_updated_vault_settings,
    get_univ3_single_data,
    get_redeem_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_normal_single_maturity_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    chain.sleep(maturity - 3600 * 24 * 6 - chain.time())
    chain.mine()
    # Disable oracle freshness check
    env.tradingModule.setMaxOracleFreshness(2 ** 32 - 1, {"from": env.notional.owner()})
    # minPrimary is calculated internally for boosted pools 
    redeemParams = get_redeem_params(0, 0, 
        get_dynamic_trade_params(
            DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
        )
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    tokensToRedeem = math.floor(vaultState["totalStrategyTokens"] * 0.5)

    # Can't settle with bad slippage setting
    with brownie.reverts():
        vault.settleVaultNormal.call(maturity, tokensToRedeem, get_redeem_params(
            0, 0, get_dynamic_trade_params(
                DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 10e6, True, get_univ3_single_data(3000)
            )
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

    vault.settleVaultNormal(maturity, tokensToRedeem, redeemParams, {"from": accounts[1]})

def test_post_maturity_single_maturity_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    # minPrimary is calculated internally for boosted pools 
    redeemParams = get_redeem_params(0, 0, 
        get_dynamic_trade_params(
            DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
        )
    )
    vaultState = env.notional.getVaultState(vault.address, maturity)
    tokensToRedeem = math.floor(vaultState["totalStrategyTokens"] * 0.5)

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

def test_emergency_single_maturity_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    vault.setStrategyVaultSettings(get_updated_vault_settings(settings, maxBalancerPoolShare=0), {"from": env.notional.owner()})
    # minPrimary is calculated internally for boosted pools 
    redeemParams = get_redeem_params(0, 0, 
        get_dynamic_trade_params(
            DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
        )
    )
    vault.settleVaultEmergency(maturity, redeemParams, {"from": env.notional.owner()})
    vaultState = env.notional.getVaultState(vault.address, maturity)
    assert vaultState["totalStrategyTokens"] == 0
