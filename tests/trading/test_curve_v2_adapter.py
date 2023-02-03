import eth_abi
import brownie
from brownie import network, accounts, MockVault
from brownie.network.state import Chain
from scripts.EnvironmentConfig import getEnvironment
from scripts.common import (
    DEX_ID, 
    TRADE_TYPE,
    ALT_ETH_ADDRESS,
    set_dex_flags,
    set_trade_type_flags
)

chain = Chain()

def get_crv_v2_single_data(sellToken, buyToken, amount, limit, pool):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_SINGLE"], 
        sellToken, 
        buyToken, 
        amount, 
        limit, 
        deadline, 
        eth_abi.encode_abi(
            ['(address)'],
            [[pool]]
        )
    ]    

def get_crv_v2_batch_data(sellToken, buyToken, amount, limit, addresses, params):
    deadline = chain.time() + 20000
    return [
        TRADE_TYPE["EXACT_IN_BATCH"], 
        sellToken, 
        buyToken, 
        amount, 
        limit, 
        deadline, 
        eth_abi.encode_abi(
            ['(address[9],uint256[3][4])'],
            [[addresses, params]]
        )
    ]    

def test_CRV_to_WETH_exact_in_single():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["CRV"].transfer(mockVault, 1000e18, {"from": env.whales["CRV"]})

    trade = get_crv_v2_single_data(
        env.tokens["CRV"].address, env.tokens["WETH"], env.tokens["CRV"].balanceOf(mockVault), 0,
        "0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511"
    )

    # Vault does not have permission to sell CRV
    with brownie.reverts():
        mockVault.executeTrade.call(DEX_ID["CURVE_V2"], trade, {"from": accounts[0]})

    # Give vault permission to sell CRV
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["CRV"].address, 
        [True, set_dex_flags(0, CURVE_V2=True), set_trade_type_flags(0, EXACT_IN_SINGLE=True)], 
        {"from": env.notional.owner()})
    crvBefore = env.tokens["CRV"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTrade(DEX_ID["CURVE_V2"], trade, {"from": accounts[0]})
    assert env.tokens["CRV"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == crvBefore - env.tokens["CRV"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore

def test_CRV_to_ETH_exact_in_batch():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["CRV"].transfer(mockVault, 1000e18, {"from": env.whales["CRV"]})

    trade = get_crv_v2_batch_data(
        env.tokens["CRV"].address, env.tokens["stETH"], env.tokens["CRV"].balanceOf(mockVault), 0,
        [
            '0xD533a949740bb3306d119CC777fa900bA034cd52', 
            '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511', 
            '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', 
            '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', 
            '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', 
            '0x0000000000000000000000000000000000000000', 
            '0x0000000000000000000000000000000000000000', 
            '0x0000000000000000000000000000000000000000', 
            '0x0000000000000000000000000000000000000000'
        ], 
        [
            [1, 0, 3], 
            [0, 1, 15], 
            [0, 0, 0], 
            [0, 0, 0]
        ]
    )

    # Vault does not have permission to sell CRV
    with brownie.reverts():
        mockVault.executeTrade.call(DEX_ID["CURVE_V2"], trade, {"from": accounts[0]})

    # Give vault permission to sell CRV
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["CRV"].address, 
        [True, set_dex_flags(0, CURVE_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})
    crvBefore = env.tokens["CRV"].balanceOf(mockVault)
    wethBefore = env.tokens["WETH"].balanceOf(mockVault)
    ret = mockVault.executeTrade(DEX_ID["CURVE_V2"], trade, {"from": accounts[0]})
    assert env.tokens["CRV"].balanceOf(mockVault) == 0
    assert ret.return_value[0] == crvBefore - env.tokens["CRV"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["WETH"].balanceOf(mockVault) - wethBefore


def test_CRV_to_stETH_exact_in_batch():
    env = getEnvironment(network.show_active())
    mockVault = MockVault.deploy(env.tradingModule, {"from": accounts[0]})

    env.tokens["CRV"].transfer(mockVault, 1000e18, {"from": env.whales["CRV"]})

    trade = get_crv_v2_batch_data(
        env.tokens["CRV"].address, env.tokens["stETH"], env.tokens["CRV"].balanceOf(mockVault), 0,
        [
            '0xD533a949740bb3306d119CC777fa900bA034cd52', 
            '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511', 
            '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', 
            '0xDC24316b9AE028F1497c275EB9192a3Ea0f67022', 
            '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84', 
            '0x0000000000000000000000000000000000000000', 
            '0x0000000000000000000000000000000000000000', 
            '0x0000000000000000000000000000000000000000', 
            '0x0000000000000000000000000000000000000000'
        ], 
        [
            [1, 0, 3], 
            [0, 1, 1], 
            [0, 0, 0], 
            [0, 0, 0]
        ]
    )

    # Vault does not have permission to sell CRV
    with brownie.reverts():
        mockVault.executeTrade.call(DEX_ID["CURVE_V2"], trade, {"from": accounts[0]})

    # Give vault permission to sell CRV
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["CRV"].address, 
        [True, set_dex_flags(0, CURVE_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    crvBefore = env.tokens["CRV"].balanceOf(mockVault)
    stETHBefore = env.tokens["stETH"].balanceOf(mockVault)
    ret = mockVault.executeTrade(DEX_ID["CURVE_V2"], trade, {"from": accounts[0]})
    assert ret.return_value[0] == crvBefore - env.tokens["CRV"].balanceOf(mockVault)
    assert ret.return_value[1] == env.tokens["stETH"].balanceOf(mockVault) - stETHBefore
