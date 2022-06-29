import pytest
import eth_abi
import brownie
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
            flags=set_flags(0, ENABLED=True, ONLY_VAULT_SETTLE=True, ALLOW_REENTRANCY=True),
            currencyId=3,
            feeRate5BPS=1, # 5 BPS fee
            minCollateralRatioBPS=500, # 5% collateral ratio
            maxBorrowMarketIndex=3 # allow up to 1 year borrows
        ),
        100_000_000e8,
        {"from": env.notional.owner()},
    )

    env.tokens['USDC'].transfer(accounts[0], 30_000e6, {"from": env.whales['USDC']})
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
            kwargs['maxBorrowRate'],
            DEX_ID[kwargs['dexId']],
            encode_exchange_data(kwargs['dexId'], 'EXACT_IN_SINGLE', kwargs['exchangeData'])
        )]
    )

@pytest.mark.only
def test_enter_vault_success(env, usdcDaiVault, accounts, tradingModule):
    markets = env.notional.getActiveMarkets(3)
    params = encode_deposit_params(
        minPurchaseAmount=Wei(107_000e18),
        minLendRate=0,
        dexId='UNISWAP_V3',
        exchangeData={
            'fee': 100
        }
    )

    # 1_074_000 gas
    txn = env.notional.enterVault(
        accounts[0],
        usdcDaiVault.address,
        10_000e6,
        markets[1][1],
        100_000e8,
        0,
        params,
        {"from": accounts[0]}
    )

def test_enter_vault_fail_lend_rate(env, usdcDaiVault, accounts):
    markets = env.notional.getActiveMarkets(3)
    params = encode_deposit_params(
        minPurchaseAmount=Wei(107_000e18),
        minLendRate=Wei(0.1e9),
        dexId='UNISWAP_V3',
        exchangeData={
            'fee': 100
        }
    )

    with brownie.reverts():
        env.notional.enterVault(
            accounts[0],
            usdcDaiVault.address,
            10_000e6,
            markets[1][1],
            100_000e8,
            0,
            params,
            {"from": accounts[0]}
        )

def test_enter_vault_fail_purchase_limit(env, usdcDaiVault, accounts):
    markets = env.notional.getActiveMarkets(3)
    params = encode_deposit_params(
        minPurchaseAmount=Wei(110_000e18),
        minLendRate=0,
        dexId='UNISWAP_V3',
        exchangeData={
            'fee': 100
        }
    )

    with brownie.reverts():
        env.notional.enterVault(
            accounts[0],
            usdcDaiVault.address,
            10_000e6,
            markets[1][1],
            100_000e8,
            0,
            params,
            {"from": accounts[0]}
        )

def test_enter_vault_fail_collateral_ratio(env, usdcDaiVault, accounts):
    markets = env.notional.getActiveMarkets(3)
    params = encode_deposit_params(
        minPurchaseAmount=Wei(99_000e18),
        minLendRate=0,
        dexId='UNISWAP_V3',
        exchangeData={
            'fee': 100
        }
    )

    with brownie.reverts():
        env.notional.enterVault(
            accounts[0],
            usdcDaiVault.address,
            4_000e6,
            markets[1][1],
            100_000e8,
            0,
            params,
            {"from": accounts[0]}
        )

def test_exit_vault_success(env, usdcDaiVault, accounts):
    markets = env.notional.getActiveMarkets(3)

    env.notional.enterVault(
        accounts[0],
        usdcDaiVault.address,
        20_000e6,
        markets[1][1],
        110_000e8,
        0,
        encode_deposit_params(
            minPurchaseAmount=Wei(107_000e18),
            minLendRate=0,
            dexId='UNISWAP_V3',
            exchangeData={
                'fee': 100
            }
        ),
        {"from": accounts[0]}
    )

    # 857_889 gas used
    txn = env.notional.exitVault(
        accounts[0],
        usdcDaiVault.address,
        accounts[0],
        12_000e8,
        10_000e8,
        0,
        encode_redeem_params(
            minPurchaseAmount=Wei(10_000e6),
            maxBorrowRate=0,
            dexId='UNISWAP_V3',
            exchangeData={
                'fee': 100
            }
        ),
        {"from": accounts[0]}
    )

#def test_exit_vault_fail_after_maturity(env, usdcDaiVault, accounts):
#def test_exit_vault_fail_borrow_limit(env, usdcDaiVault, accounts):
#def test_exit_vault_fail_purchase_limit(env, usdcDaiVault, accounts):
#def test_exit_vault_fail_collateral_ratio(env, usdcDaiVault, accounts):

#def test_roll_vault_reverts(env, usdcDaiVault, accounts):
#def test_liquidate_vault_success(env, usdcDaiVault, accounts):

def test_settle_vault_success(env, usdcDaiVault, accounts):
    markets = env.notional.getActiveMarkets(3)
    maturity = markets[1][1]

    env.notional.enterVault(
        accounts[0],
        usdcDaiVault.address,
        20_000e6,
        maturity,
        110_000e8,
        0,
        encode_deposit_params(
            minPurchaseAmount=Wei(107_000e18),
            minLendRate=0,
            dexId='UNISWAP_V3',
            exchangeData={
                'fee': 100
            }
        ),
        {"from": accounts[0]}
    )

    chain.mine(1, timestamp=markets[0][1])
    env.notional.initializeMarkets(2, False, {"from": accounts[0]})
    env.notional.initializeMarkets(3, False, {"from": accounts[0]})

    chain.mine(1, timestamp=markets[1][1])
    env.notional.initializeMarkets(2, False, {"from": accounts[0]})
    env.notional.initializeMarkets(3, False, {"from": accounts[0]})
    
    txn = usdcDaiVault.settleVault(
        maturity,
        encode_redeem_params(
            minPurchaseAmount=Wei(129_700e6),
            maxBorrowRate=0,
            dexId='UNISWAP_V3',
            exchangeData={
                'fee': 100
            }
        ),
        {"from": accounts[1]}
    )

#def test_settle_vault_fail_purchase_limit(env, usdcDaiVault, accounts):
#def test_settle_vault_insolvent(env, usdcDaiVault, accounts):