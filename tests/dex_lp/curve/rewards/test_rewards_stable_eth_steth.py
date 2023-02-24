from brownie import ZERO_ADDRESS, Wei, accounts
from tests.fixtures import *
from tests.dex_lp.helpers import get_metastable_amounts
from tests.dex_lp.acceptance import ETHPrimaryContext, claim_rewards, reinvest_reward
from scripts.common import (
    DEX_ID, 
    TRADE_TYPE
)

chain = Chain()

def test_claim_rewards(StratCurveStableETHstETH):
    claim_rewards(ETHPrimaryContext(*StratCurveStableETHstETH), 
        50e18,
        100e8, 
        accounts[0],
        {
            "CRV": 10644377099247555,
            "CVX": 308500225322579,
            "LDO": 10261520016963064477
        }
    )

def test_reinvest_reward(StratCurveStableETHstETH):
    context = ETHPrimaryContext(*StratCurveStableETHstETH)
    env = context.env
    rewardAmount = Wei(10000e18)
    tradeParams = "(uint16,uint8,uint256,bool,bytes)"
    singleSidedRewardTradeParams = "(address,address,uint256,{})".format(tradeParams)
    proportional2TokenRewardTradeParams = "({},{})".format(singleSidedRewardTradeParams, singleSidedRewardTradeParams)
    (primaryAmount, secondaryAmount) = get_metastable_amounts(context.vault.getStrategyContext()["poolContext"], rewardAmount)
    poolClaimBefore = context.vault.getStrategyContext()["baseStrategy"]["vaultState"]["totalPoolClaim"]
    primaryTradeAddresses = [
        '0xD533a949740bb3306d119CC777fa900bA034cd52', 
        '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511', 
        '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', 
        '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', 
        '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', 
        '0x0000000000000000000000000000000000000000', 
        '0x0000000000000000000000000000000000000000', 
        '0x0000000000000000000000000000000000000000', 
        '0x0000000000000000000000000000000000000000'
    ]
    primaryTradeParams = [
        [1, 0, 3], 
        [0, 1, 15], 
        [0, 0, 0], 
        [0, 0, 0]
    ]
    secondaryTradeAddresses = [
        '0xD533a949740bb3306d119CC777fa900bA034cd52', 
        '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511', 
        '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', 
        '0xDC24316b9AE028F1497c275EB9192a3Ea0f67022', 
        '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84', 
        '0x0000000000000000000000000000000000000000', 
        '0x0000000000000000000000000000000000000000', 
        '0x0000000000000000000000000000000000000000', 
        '0x0000000000000000000000000000000000000000'
    ] 
    secondaryTradeParams = [
        [1, 0, 3], 
        [0, 1, 1], 
        [0, 0, 0], 
        [0, 0, 0]
    ]
    rewardParams = [eth_abi.encode_abi(
        [proportional2TokenRewardTradeParams],
        [[
            [
                env.tokens["CRV"].address,
                ZERO_ADDRESS,
                primaryAmount,
                [
                    DEX_ID["CURVE_V2"],
                    TRADE_TYPE["EXACT_IN_BATCH"],
                    0,
                    False,
                    eth_abi.encode_abi(
                        ['(address[9],uint256[3][4])'],
                        [[primaryTradeAddresses, primaryTradeParams]]
                    )
                ]
            ],
            [
                env.tokens["CRV"].address,
                env.tokens["stETH"].address,
                secondaryAmount,
                [
                    DEX_ID["CURVE_V2"],
                    TRADE_TYPE["EXACT_IN_BATCH"],
                    0,
                    False,
                    eth_abi.encode_abi(
                        ['(address[9],uint256[3][4])'],
                        [[secondaryTradeAddresses, secondaryTradeParams]]
                    )
                ]
            ]
        ]]
    ), 0]

    reinvest_reward(context, accounts[0], "CRV", rewardAmount, rewardParams, poolClaimBefore, 6002022696816520749)
