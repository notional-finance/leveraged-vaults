import pytest
from brownie import ETH_ADDRESS, Wei
from tests.fixtures import *
from scripts.common import (
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_claim_rewards_success(StratStableETHstETH):
    pass

def test_reinvest_rewards_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    env.tokens["BAL"].transfer(vault.address, 50e18, {"from": env.whales["BAL"]})

    packedEncoder = eth_abi.codec.ABIEncoder(eth_abi.registry.registry_packed)
    vault.reinvestReward([eth_abi.encode_abi(
        ['''(uint16,
            (uint8,address,address,uint256,uint256,uint256,bytes),
            uint16,
            (uint8,address,address,uint256,uint256,uint256,bytes))
         '''],
        [[
            DEX_ID["CURVE"],
            [
                TRADE_TYPE["EXACT_IN_SINGLE"],
                env.tokens["BAL"].address,
                ETH_ADDRESS,
                Wei(50e18),
                0,
                chain.time() + 10000,
                bytes(0)             
            ],
            DEX_ID["CURVE"],
            [
                TRADE_TYPE["EXACT_IN_SINGLE"],
                ETH_ADDRESS,
                env.tokens["wstETH"].address,
                Wei(10e18),
                0,
                chain.time() + 10000,
                bytes(0)       
            ]
        ]]
    ), 0],
        {"from": env.whales["USDC"]}
    )
