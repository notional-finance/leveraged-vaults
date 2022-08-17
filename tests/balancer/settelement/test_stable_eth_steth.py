
import pytest
import eth_abi
import brownie
from brownie import ZERO_ADDRESS, Wei, accounts
from brownie.network.state import Chain
from tests.fixtures import *
from scripts.common import (
    get_deposit_params, 
    get_dynamic_trade_params,
    DEX_ID,
    TRADE_TYPE
)

chain = Chain()

def test_normal_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH

def test_normal_single_maturity_incremental_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH

def test_post_maturity_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH

def test_emergency_single_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH