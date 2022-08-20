import pytest
import eth_abi
from brownie.network import Chain
from brownie import network, Contract
from scripts.EnvironmentConfig import getEnvironment

DEX_ID = {
    'UNUSED': 0,
    'UNISWAP_V2': 1,
    'UNISWAP_V3': 2,
    'ZERO_EX': 3,
    'BALANCER_V2': 4,
    'CURVE': 5,
    'NOTIONAL_VAULT': 6
}

def encode_exchange_data(dex, tradeType, params):
    if dex == 'UNISWAP_V3' and tradeType == 'EXACT_IN_SINGLE':
        return eth_abi.encode_abi(['(uint24)'], [tuple([params['fee']])])

@pytest.fixture(scope="module", autouse=True)
def env():
    name = network.show_active()
    if name == 'goerli-fork':
        environment = getEnvironment('goerli')
        environment.notional.upgradeTo('0x433a0679756D6EB110E8Ff730d06DBee5D9F5db5', {'from': environment.owner})
        return environment
    if name == 'mainnet-fork':
        return getEnvironment('mainnet')

def set_flags(flags, **kwargs):
    binList = list(format(flags, "b").rjust(16, "0"))
    if "ENABLED" in kwargs:
        binList[0] = "1"
    if "ALLOW_ROLL_POSITION" in kwargs:
        binList[1] = "1"
    if "ONLY_VAULT_ENTRY" in kwargs:
        binList[2] = "1"
    if "ONLY_VAULT_EXIT" in kwargs:
        binList[3] = "1"
    if "ONLY_VAULT_ROLL" in kwargs:
        binList[4] = "1"
    if "ONLY_VAULT_DELEVERAGE" in kwargs:
        binList[5] = "1"
    if "ONLY_VAULT_SETTLE" in kwargs:
        binList[6] = "1"
    if "ALLOW_REENTRANCY" in kwargs:
        binList[7] = "1"
    return int("".join(reversed(binList)), 2)


def get_vault_config(**kwargs):
    return [
        kwargs.get("flags", 0),  # 0: flags
        kwargs.get("currencyId", 1),  # 1: currency id
        kwargs.get("minAccountBorrowSize", 100_000),  # 2: min account borrow size
        kwargs.get("minCollateralRatioBPS", 2000),  # 3: 20% collateral ratio
        kwargs.get("feeRate5BPS", 20),  # 4: 1% fee
        kwargs.get("liquidationRate", 104),  # 5: 4% liquidation discount
        kwargs.get("reserveFeeShare", 20),  # 6: 20% reserve fee share
        kwargs.get("maxBorrowMarketIndex", 2),  # 7: 20% reserve fee share
        kwargs.get("maxDeleverageCollateralRatioBPS", 4000),  # 8: 40% max collateral ratio
        kwargs.get("secondaryBorrowCurrencies", [0, 0]),  # 9: none set
    ]
