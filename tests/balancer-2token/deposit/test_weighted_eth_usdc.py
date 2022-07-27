import pytest
import eth_abi
from brownie import Wei
from tests.fixtures import *

def test_enter_vault_low_leverage_success(Strat50ETH50USDC):
    (env, vault, mockTwoTokenAuraStrategyUtils) = Strat50ETH50USDC
    maturity = env.notional.getActiveMarkets(1)[0][1]
    strategyContext = vault.getStrategyContext()
    env.notional.enterVault(
        env.whales["ETH"],
        vault.address,
        10e18,
        maturity,
        5e8,
        0,
        eth_abi.encode_abi(
            ['(uint256,uint256,uint32,uint32,bytes)'],
            [[
                0,
                Wei(env.mockWeighted2TokenOracleMath.getOptimalSecondaryBorrowAmount(
                    strategyContext["oracleContext"],
                    strategyContext["poolContext"],
                    15e18) * 1e2),
                0,
                0,
                bytes(0)
            ]]
        ),
        {"from": env.whales["ETH"], "value": 10e18}
    )
