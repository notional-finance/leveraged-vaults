import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import enterMaturity, exitVaultPercent
from scripts.common import (
    get_deposit_params, 
    get_dynamic_trade_params,
    get_redeem_params,
    get_univ3_single_data,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_full_redemption_success(StratBoostedPoolUSDCPrimary):
    (env, vault) = StratBoostedPoolUSDCPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e6
    env.tokens["USDC"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["USDC"]})
    maturity = enterMaturity(env, vault, 3, 0, depositAmount, primaryBorrowAmount, env.whales["USDC"])
    primaryAmountBefore = env.tokens["USDC"].balanceOf(env.whales["USDC"])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    exitVaultPercent(env, vault, env.whales["USDC"], 1.0, redeemParams)
