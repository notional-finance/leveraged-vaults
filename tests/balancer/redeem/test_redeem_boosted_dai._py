import pytest
from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import check_invariant, check_account, enterMaturity, exitVaultPercent
from scripts.common import get_dynamic_trade_params, get_redeem_params, get_univ3_single_data, DEX_ID, TRADE_TYPE

chain = Chain()

def test_single_maturity_full_redemption_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    primaryAmountBefore = env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    exitVaultPercent(env, vault, env.whales["DAI_EOA"], 1.0, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"]], [maturity])
    check_account(env, vault, env.whales["DAI_EOA"], 0, 0)
    assert pytest.approx(env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"]) - primaryAmountBefore, rel=5e-2) == depositAmount

def test_single_maturity_partial_redemption_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    vaultSharesBefore =  env.notional.getVaultAccount(env.whales["DAI_EOA"], vault.address)["vaultShares"]
    primaryAmountBefore = env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, env.whales["DAI_EOA"], 0.5, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"]], [maturity])
    check_account(env, vault, env.whales["DAI_EOA"], vaultSharesBefore - sharesRedeemed, primaryBorrowAmount - fCashRepaid)
    assert pytest.approx(env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"]) - primaryAmountBefore, rel=5e-2) == depositAmount * 0.5

    exitVaultPercent(env, vault, env.whales["DAI_EOA"], 1, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"]], [maturity])
    check_account(env, vault, env.whales["DAI_EOA"], 0, 0)
    assert pytest.approx(env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"]) - primaryAmountBefore, rel=5e-2) == depositAmount

def test_multiple_maturities_full_redemption_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].transfer(accounts[0], 20000e18, {"from": env.whales["DAI_EOA"]})
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": accounts[0]})
    maturity1 = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    maturity2 = enterMaturity(env, vault, 2, 1, depositAmount, primaryBorrowAmount, accounts[0])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    primaryAmountBefore1 = env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"])
    primaryAmountBefore2 = env.tokens["DAI"].balanceOf(accounts[0])
    exitVaultPercent(env, vault, env.whales["DAI_EOA"], 1.0, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"], accounts[0]], [maturity1, maturity2])
    check_account(env, vault, env.whales["DAI_EOA"], 0, 0)
    assert pytest.approx(env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"]) - primaryAmountBefore1, rel=5e-2) == depositAmount

    exitVaultPercent(env, vault, accounts[0], 1.0, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"], accounts[0]], [maturity1, maturity2])
    check_account(env, vault, accounts[0], 0, 0)
    assert pytest.approx(env.tokens["DAI"].balanceOf(accounts[0]) - primaryAmountBefore2, rel=5e-2) == depositAmount

def test_multiple_maturities_partial_redemption_success(StratBoostedPoolDAIPrimary):
    (env, vault) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].transfer(accounts[0], 20000e18, {"from": env.whales["DAI_EOA"]})
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": accounts[0]})
    maturity1 = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    maturity2 = enterMaturity(env, vault, 2, 1, depositAmount, primaryBorrowAmount, accounts[0])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    vaultSharesBefore1 =  env.notional.getVaultAccount(env.whales["DAI_EOA"], vault.address)["vaultShares"]
    vaultSharesBefore2 =  env.notional.getVaultAccount(accounts[0], vault.address)["vaultShares"]
    primaryAmountBefore1 = env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"])
    primaryAmountBefore2 = env.tokens["DAI"].balanceOf(accounts[0])

    (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, env.whales["DAI_EOA"], 0.5, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"], accounts[0]], [maturity1, maturity2])
    check_account(env, vault, env.whales["DAI_EOA"], vaultSharesBefore1 - sharesRedeemed, primaryBorrowAmount - fCashRepaid)
    assert pytest.approx(env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"]) - primaryAmountBefore1, rel=5e-2) == depositAmount * 0.5
    (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, accounts[0], 0.5, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"], accounts[0]], [maturity1, maturity2])
    check_account(env, vault, accounts[0], vaultSharesBefore2 - sharesRedeemed, primaryBorrowAmount - fCashRepaid)
    assert pytest.approx(env.tokens["DAI"].balanceOf(accounts[0]) - primaryAmountBefore2, rel=5e-2) == depositAmount * 0.5

    exitVaultPercent(env, vault, env.whales["DAI_EOA"], 1, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"], accounts[0]], [maturity1, maturity2])
    check_account(env, vault, env.whales["DAI_EOA"], 0, 0)
    assert pytest.approx(env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"]) - primaryAmountBefore1, rel=5e-2) == depositAmount
    exitVaultPercent(env, vault, accounts[0], 1, redeemParams)
    check_invariant(env, vault, [env.whales["DAI_EOA"], accounts[0]], [maturity1, maturity2])
    check_account(env, vault, accounts[0], 0, 0)
    assert pytest.approx(env.tokens["DAI"].balanceOf(accounts[0]) - primaryAmountBefore2, rel=5e-2) == depositAmount
