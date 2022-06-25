import pytest
import eth_abi
from brownie.convert.datatypes import Wei, HexString
from brownie.network import Chain
from brownie import network, Contract
from scripts.EnvironmentConfig import getEnvironment
from fixtures import *

chain = Chain()

@pytest.fixture(scope="module", autouse=True)
def usdcDaiVault(env, CrossCurrencyfCashVault, nProxy, tradingModule, accounts):
    impl = CrossCurrencyfCashVault.deploy(env.notional.address, tradingModule.address, {"from": accounts[0]})
    initializeCallData = impl.initialize.encode_input(
        "USDC/DAI Cross Currency fCash",
        3, 2, 0.995e18
    )
    proxy = nProxy.deploy(impl.address, initializeCallData, {"from": accounts[0]})
    vault = Contract.from_abi("CrossCurrency", proxy.address, abi=CrossCurrencyfCashVault.abi)

    env.notional.updateVault(
        vault.address,
        get_vault_config(
            flags=set_flags(0, ENABLED=True, ONLY_VAULT_SETTLE=True, ALLOW_REENTRNACY=True),
            currencyId=3,
            feeRate5BPS=1, # 5 BPS fee
            minCollateralRatioBPS=500, # 5% collateral ratio
            maxBorrowMarketIndex=3 # allow up to 1 year borrows
        ),
        100_000_000e8,
        {"from": env.notional.owner()},
    )

    env.tokens['USDC'].transfer(accounts[0], 10_000e6, {"from": env.whales['USDC']})
    env.tokens['USDC'].approve(env.notional.address, 2 ** 255, {"from": accounts[0]})

    return vault

def encode_deposit_params(**kwargs):
    return eth_abi.encode_abi(
        ['(uint256,uint32,uint16,bytes)'],
        [(
            kwargs['minPurchaseAmount'],
            kwargs['minLendRate'],
            DEX_ID[kwargs['dexId']],
            encode_exchange_data(kwargs['dexId'], 'EXACT_IN_SINGLE', kwargs['exchangeData'])
        )]
    )

def encode_redeem_params(**kwargs):
    return eth_abi.encode_abi(
        ['(uint256,uint32,uint16,bytes)'],
        [(
            kwargs['minPurchaseAmount'],
            kwargs['minBorrowRate'],
            DEX_ID[kwargs['dexId']],
            encode_exchange_data(kwargs['dexId'], 'EXACT_IN_SINGLE', kwargs['exchangeData'])
        )]
    )

def test_enter_vault_success(env, usdcDaiVault, accounts, tradingModule):
    markets = env.notional.getActiveMarkets(3)
    params = encode_deposit_params(
        minPurchaseAmount=Wei(99_000e18),
        minLendRate=0,
        dexId='UNISWAP_V3',
        exchangeData={
            'fee': 100
        }
    )
    txn = env.notional.enterVault(
        accounts[0],
        usdcDaiVault.address,
        5_000e6,
        markets[1][1],
        100_000e8,
        0,
        params,
        {"from": accounts[0]}
    )

    assert False
#def test_enter_vault_fail_lend_rate(env, usdcDaiVault, accounts):
#def test_enter_vault_fail_purchase_limit(env, usdcDaiVault, accounts):
#def test_enter_vault_fail_collateral_ratio(env, usdcDaiVault, accounts):

#def test_exit_vault_success(env, usdcDaiVault, accounts):
#def test_exit_vault_fail_after_maturity(env, usdcDaiVault, accounts):
#def test_exit_vault_fail_borrow_limit(env, usdcDaiVault, accounts):
#def test_exit_vault_fail_purchase_limit(env, usdcDaiVault, accounts):

#def test_roll_vault_reverts(env, usdcDaiVault, accounts):
#def test_liquidate_vault_success(env, usdcDaiVault, accounts):

#def test_settle_vault_success(env, usdcDaiVault, accounts):
#def test_settle_vault_fail_purchase_limit(env, usdcDaiVault, accounts):
#def test_settle_vault_insolvent(env, usdcDaiVault, accounts):