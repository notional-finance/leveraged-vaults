import pytest
import eth_abi
from brownie import Wei
from tests.fixtures import *
from scripts.common import get_deposit_params

def test_enter_vault_low_leverage_success(Strat50ETH50USDC):
    (env, vault, mock) = Strat50ETH50USDC
    maturity = env.notional.getActiveMarkets(1)[0][1]
    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        10e18,
        maturity,
        5e8,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": 10e18}
    )
