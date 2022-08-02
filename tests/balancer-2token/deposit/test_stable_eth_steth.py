import pytest
import eth_abi
from brownie import ZERO_ADDRESS, Wei, accounts
from tests.fixtures import *

def test_single_maturity_low_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
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

def test_single_maturity_high_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity = env.notional.getActiveMarkets(1)[0][1]
    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        10e18,
        maturity,
        20e8,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": 10e18}
    )

def test_multiple_maturities_low_leverage_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    maturity1 = env.notional.getActiveMarkets(1)[0][1]
    maturity2 = env.notional.getActiveMarkets(1)[1][1]
    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        10e18,
        maturity1,
        5e8,
        0,
        get_deposit_params(),
        {"from": env.whales["ETH"], "value": 10e18}
    )
    env.whales["ETH"].transfer(accounts[0], 100e18)
    env.notional.enterVault(
        accounts[0],
        vault.address,
        10e18,
        maturity2,
        5e8,
        0,
        get_deposit_params(),
        {"from": accounts[0], "value": 10e18}
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