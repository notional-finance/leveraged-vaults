import pytest
import eth_abi
from brownie import Wei
from tests.fixtures import *

def test_enter_vault_low_leverage_success(StratBoostedPoolDAIPrimary):
    (env, vault, mockTwoTokenAuraStrategyUtils) = StratBoostedPoolDAIPrimary
    maturity = env.notional.getActiveMarkets(1)[0][1]
    env.notional.enterVault(
        env.whales["DAI"],
        vault.address,
        10e18,
        maturity,
        5e8,
        0,
        get_deposit_params(),
        {"from": env.whales["DAI"], "value": 10e18}
    )

def get_deposit_params():
    eth_abi.encode_abi(
        ['(uint256,uint256,uint32,uint32,bytes)'],
        [[
            0,
            0,
            0,
            0,
            bytes(0)
        ]]
    )