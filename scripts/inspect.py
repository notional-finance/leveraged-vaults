# flake8: noqa
import json
from brownie import network, interface, FlashLiquidator, accounts
from brownie.network.contract import Contract

def get_router_args(router):
    return [
        router.GOVERNANCE(),
        router.VIEWS(),
        router.INITIALIZE_MARKET(),
        router.NTOKEN_ACTIONS(),
        router.BATCH_ACTION(),
        router.ACCOUNT_ACTION(),
        router.ERC1155(),
        router.LIQUIDATE_CURRENCY(),
        router.LIQUIDATE_FCASH(),
        router.TREASURY(),
        router.CALCULATION_VIEWS(),
        router.VAULT_ACCOUNT_ACTION(),
        router.VAULT_ACTION(),
        router.VAULT_LIQUIDATION_ACTION(),
        router.VAULT_ACCOUNT_HEALTH(),
    ]

def get_addresses():
    networkName = network.show_active()
    if networkName == "mainnet-fork" or networkName == "mainnet-current" or networkName == "mainnet":
        networkName = "mainnet"
    if networkName == "arbitrum-fork" or networkName == "arbitrum-current":
        networkName = "arbitrum-one"
    output_file = "v3.{}.json".format(networkName)
    addresses = None
    with open(output_file, "r") as f:
        addresses = json.load(f)

    if networkName == "mainnet":
        liquidators = [
            FlashLiquidator.at('0x77B4507981607402aB9692A1628053c39eCf4fFb'),
            FlashLiquidator.at('0xA573bD9cAF777B354f46f635Ca339d074bD40A66'),
            FlashLiquidator.at('0x12AEC56DFc38413C5FEa5506041F49416b17BdA1')
        ]
    elif networkName == "arbitrum-one":
        liquidators = [
            FlashLiquidator.at('0xe8f28Cf944aBCFD98dACdcbA284AcFC56a6E929b'),
            FlashLiquidator.at('0x24B5FF402440aB10618F3798253d2cD5801E40F7'),
            FlashLiquidator.at('0xc91864Be1b097c9c85565cDB013Ba2307FFB492a')
        ]

    notional = Contract.from_abi("Notional", addresses["notional"], abi=interface.NotionalProxy.abi)
    tradingModule = Contract.from_abi("TradingModule", addresses["tradingModule"], abi=interface.ITradingModule.abi)

    return (addresses, notional, networkName, tradingModule, liquidators)

# Are liquidations failing? Check these things:
# Datadog Dashboard: https://app.datadoghq.com/dashboard/4kr-s7n-9nv/v3-risk-monitoring
#  1. Are there sufficient funds on the relayer? (https://etherscan.io/address/0xbcf0fa01ab57c6e8ab322518ad1b4b86778f08e1)
#  2. Are any of the liquidator addresses above holding a position in the vault?
#  3. Do you need to increase the gas limit?

# Setup:
# 1. When running in Brownie, you need to comment out one of the contracts/global/*/Deployments.sol files. It does
#    not matter which one as long as you are not deploying new contracts. (during liquidation you are not).
# 2. Ensure your hot wallet is loaded into the brownie account store:
#       `brownie accounts new <YOUR_WALLET_NAME>`
# 3. View the liquidation calldata at one of these URLs:
#       - https://arbitrum.vault-liquidator.notional.finance/<VAULT_ADDRESS>
#       - https://mainnet.vault-liquidator.notional.finance/<VAULT_ADDRESS>

def main():
    (addresses, notional, networkName, tradingModule, liquidators) = get_addresses()

    # Unlock your account here:
    # accounts.load("<YOUR_WALLET_NAME>")

    # Choose a liquidator (any one will do) and decode the inputs:
    # liquidators[0].decode_input("<CALLDATA_FROM_BATCHES>")[1]
    # Make sure you extract the array from the output and put quotes around the byte string

    # Copy these args and execute:
    # liquidators[0].flashLiquidate(<ARGS_FROM_OUTPUT>)

    # Alternatively, you can copy the "batchArgs" and then update them as you see fit,
    # perhaps increasing the flash loan amount or reducing the number of accounts
    # being liquidated.
    
    # WARNING: you cannot liquidate two accounts with different maturities in one batch,
    # you will need to use two liquidator contracts or wait the 1 minute exit vault time
    # between liquidation contracts.
