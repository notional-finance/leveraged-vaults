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
    get_univ3_single_data,
    get_redeem_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_single_maturity_full_redemption_success(StratBoostedPoolDAIPrimary):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
    primaryBorrowAmount = 5000e8
    depositAmount = 10000e18
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    maturity = enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"])
    primaryAmountBefore = env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"])
    redeemParams = get_redeem_params(0, 0, get_dynamic_trade_params(
        DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, True, get_univ3_single_data(3000)
    ))
    exitVaultPercent(env, vault, env.whales["DAI_EOA"], 1.0, redeemParams)
 