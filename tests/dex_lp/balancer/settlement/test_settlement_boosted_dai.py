
from brownie import accounts, Wei
from tests.fixtures import *
from tests.dex_lp.acceptance import (
    DAIPrimaryContext, 
    normal_settlement,
    post_maturity_settlement,
    emergency_settlement
)
from scripts.common import (
    get_univ3_single_data,
    DEX_ID,
    TRADE_TYPE
)

def test_normal_single_maturity(StratBoostedPoolDAIPrimary):
    redeemParams = [0, 0, [DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(3e6), True, get_univ3_single_data(3000)]]
    normal_settlement(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        10000e18, 
        5000e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.5
    )

def test_post_maturity_single_maturity(StratBoostedPoolDAIPrimary):
    redeemParams = [0, 0, [DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(5e6), True, get_univ3_single_data(3000)]]
    post_maturity_settlement(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        10000e18, 
        5000e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.3
    )

def test_emergency_single_maturity(StratBoostedPoolDAIPrimary):
    redeemParams = [0, 0, [DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(4e6), True, get_univ3_single_data(3000)]]
    emergency_settlement(
        DAIPrimaryContext(*StratBoostedPoolDAIPrimary), 
        10000e18, 
        5000e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams
    )
