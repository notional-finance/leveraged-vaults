import pytest
from tests.fixtures import *

def test_claim_rewards_success():

def test_reinvest_rewards_success(Strat50ETH50USDC):
    (env, vault, mockTwoTokenAuraStrategyUtils) = Strat50ETH50USDC
    env.tokens["BAL"].transfer(vault.address, 50e18, {"from": env.whales["BAL"]})

    packedEncoder = eth_abi.codec.ABIEncoder(eth_abi.registry.registry_packed)
    vault.reinvestReward([eth_abi.encode_abi(
        ['(uint16,(uint8,address,address,uint256,uint256,uint256,bytes),uint16,(uint8,address,address,uint256,uint256,uint256,bytes))'],
        [[
            1,
            [
                0,
                env.tokens["BAL"].address,
                ETH_ADDRESS,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(uint24)'],
                    [[3000]]
                )                   
            ],
            1,
            [
                2,
                env.tokens["BAL"].address,
                env.tokens["USDC"].address,
                Wei(10e18),
                0,
                chain.time() + 10000,
                eth_abi.encode_abi(
                    ['(bytes)'],
                    [[
                        packedEncoder.encode_abi(
                            ["address", "uint24", "address", "uint24", "address"], 
                            [
                                env.tokens["BAL"].address, 
                                3000, 
                                env.tokens["WETH"].address,
                                3000, 
                                env.tokens["USDC"].address
                            ]
                        )                 
                    ]]
                )          
            ]
        ]]
    ), 0],
        {"from": env.whales["USDC"]}
    )
