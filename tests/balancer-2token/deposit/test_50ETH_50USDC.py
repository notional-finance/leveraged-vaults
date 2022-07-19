import pytest
import eth_abi
from brownie import network, Wei
from tests.fixtures import *
from scripts.BalancerEnvironment import getEnvironment

@pytest.fixture(scope="module", autouse=True)
def eth50USDC50Vault():
    return getEnvironment("Strat50ETH50USDC", network.show_active())

def test_enter_vault_low_leverage_success(eth50USDC50Vault):
    vault = eth50USDC50Vault.strategyVault
    maturity = eth50USDC50Vault.notional.getActiveMarkets(1)[0][1]
    eth50USDC50Vault.notional.enterVault(
        eth50USDC50Vault.whales["ETH"],
        vault.address,
        10e18,
        maturity,
        5e8,
        0,
        eth_abi.encode_abi(
            ['(uint256,uint256,uint32,uint32)'],
            [[
                0,
                Wei(eth50USDC50Vault.mockBalancerUtils.getOptimalSecondaryBorrowAmount(vault.getOracleContext(), 15e18) * 1e2),
                0,
                0
            ]]
        ),
        {"from": eth50USDC50Vault.whales["ETH"], "value": 10e18}
    )
