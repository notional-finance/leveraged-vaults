import pytest
import eth_abi
from brownie import Wei
from tests.fixtures import *

def test_enter_vault_low_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault, mock) = StratBoostedPoolDAIPrimary
    maturity = env.notional.getActiveMarkets(2)[0][1]
    env.tokens["DAI"].approve(env.notional, 2 ** 256 - 1, {"from": env.whales["DAI_EOA"]})
    env.notional.enterVault(
        env.whales["DAI_EOA"],
        vault.address,
        10000e18,
        maturity,
        5000e8,
        0,
        get_deposit_params(),
        {"from": env.whales["DAI_EOA"]}
    )

def get_deposit_params():
    return eth_abi.encode_abi(
        ['(uint256,uint256,uint32,uint32,bytes)'],
        [[
            0,
            0,
            0,
            0,
            bytes(0)
        ]]
    )