from brownie import accounts, Wei
from tests.fixtures import *
from tests.balancer.acceptance import (
    USDCPrimaryContext, 
    normal_settlement,
    emergency_settlement,
    post_maturity_settlement
)
from scripts.common import (
    get_univ3_single_data,
    DEX_ID,
    TRADE_TYPE
)

def test_normal_single_maturity(StratEulerBoostedPoolUSDCPrimary):
    redeemParams = [0, 0, [DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(3e6), True, get_univ3_single_data(3000)]]
    normal_settlement(
        USDCPrimaryContext(*StratEulerBoostedPoolUSDCPrimary), 
        10000e6, 
        5000e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.5
    )

def test_post_maturity_single_maturity(StratEulerBoostedPoolUSDCPrimary):
    redeemParams = [0, 0, [DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(5e6), True, get_univ3_single_data(3000)]]
    post_maturity_settlement(
        USDCPrimaryContext(*StratEulerBoostedPoolUSDCPrimary), 
        10000e6, 
        5000e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams,
        0.3
    )

def test_emergency_single_maturity_success(StratEulerBoostedPoolUSDCPrimary):
    redeemParams = [0, 0, [DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], Wei(4e6), True, get_univ3_single_data(3000)]]
    emergency_settlement(
        USDCPrimaryContext(*StratEulerBoostedPoolUSDCPrimary), 
        10000e6, 
        5000e8, 
        0, 
        accounts[0], 
        accounts[1],
        redeemParams
    )
