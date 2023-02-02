import eth_abi
from brownie import network, accounts, MockVault
from brownie.network.state import Chain
from scripts.EnvironmentConfig import getEnvironment
from scripts.common import (
    DEX_ID, 
    TRADE_TYPE,
    set_dex_flags,
    set_trade_type_flags
)

chain = Chain()

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

    # Give vault permission to sell stETH
    env.tradingModule.setTokenPermissions(
        mockVault.address, 
        env.tokens["CRV"].address, 
        [True, set_dex_flags(0, CURVE_V2=True), set_trade_type_flags(0, EXACT_IN_BATCH=True)], 
        {"from": env.notional.owner()})

    crvBefore = env.tokens["CRV"].balanceOf(mockVault)
    stETHBefore = env.tokens["stETH"].balanceOf(mockVault)
    ret = mockVault.executeTrade(DEX_ID["CURVE_V2"], trade, {"from": accounts[0]})
