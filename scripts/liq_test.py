from brownie import accounts, interface, MockEuler, FlashLiquidator
from scripts.common import (
    get_redeem_params, 
    get_dynamic_trade_params, 
    get_univ3_single_data,
    DEX_ID,
    TRADE_TYPE
)

def main():
    notional = interface.NotionalProxy("0xD8229B55bD73c61D840d339491219ec6Fa667B0a")
    deployer = accounts.at("0x6DdBFfD34deeF150C1a8848f479b0cE2bE77A294", force=True)
    cethWhale = accounts.at("0x424da3efc0dc677be66afe1967fb631fabb86799", force=True)
    ceth = interface.IERC20("0xc4d0e86dc348965d24d431F0430110948B564a85")
    ceth.approve(notional.address, 2**256-1, {"from": cethWhale})
    mockEuler = MockEuler.deploy("0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1", {"from": deployer})
    weth = interface.WETH9("0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1")
    weth.deposit({"from": deployer, "value": 1e18})
    print(weth.balanceOf(deployer.address))
    weth.transfer(mockEuler, weth.balanceOf(deployer.address), {"from": deployer})
    vault = "0xE767769b639Af18dbeDc5FB534E263fF7BE43456"
    flashLiq = FlashLiquidator.deploy("0xD8229B55bD73c61D840d339491219ec6Fa667B0a", mockEuler.address, mockEuler.address, {"from": deployer})
    flashLiq.enableCurrencies([1], {"from": deployer})
    redeemParams = get_redeem_params(0, 0, 
        get_dynamic_trade_params(
            DEX_ID["UNISWAP_V3"], TRADE_TYPE["EXACT_IN_SINGLE"], 5e6, False, get_univ3_single_data(3000)
        )
    )