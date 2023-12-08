#!/bin/bash
set -e

export FOUNDRY_PROFILE=deployment
export UPGRADE_VAULT=true
export UPDATE_CONFIG=false

source .env
# forge script tests/SingleSidedLP/pools/FRAX_USDC_e.t.sol:Test_FRAX \
#     -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
#     --gas-limit 1125899906842624 --chain 42161 --account ARBITRUM-ONE_DEPLOYER

# forge script tests/SingleSidedLP/pools/rETH_WETH.t.sol:Test_rETH \
#     -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
#     --gas-limit 1125899906842624 --chain 42161 --account ARBITRUM-ONE_DEPLOYER

# forge script tests/SingleSidedLP/pools/USDC_DAI_USDT_USDC_e.t.sol:Test_USDC \
#     -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
#     --gas-limit 1125899906842624 --chain 42161 --account ARBITRUM-ONE_DEPLOYER

# NOTE: if this fails on estimating gas when executing the deployment we have to manually
# send the transaction. Verification will not be required if the code has not changed.
# FRAX_USDC
cast send --account ARBITRUM-ONE_DEPLOYER --chain 42161  --gas-limit 120935302 --gas-price 0.1gwei --create \
# 0xA99b6375490f6861390CFeb3d18C3F177d325CF9

# rETH_WETH
cast send --account ARBITRUM-ONE_DEPLOYER --chain 42161  --gas-limit 120935302 --gas-price 0.1gwei --create \
# 0xF47f6D45284cFFe42881f437a5bA8Dabb178F3e2


# USDC_DAI_USDT_USDC_e
cast send --account ARBITRUM-ONE_DEPLOYER --chain 42161  --gas-limit 120935302 --gas-price 0.1gwei --create \
# 0x434A3c376C8900E57476608872282f29565f8eeC



forge verify-contract 0xF47f6D45284cFFe42881f437a5bA8Dabb178F3e2 \
    contracts/vaults/BalancerComposableAuraVault.sol:BalancerComposableAuraVault -c 42161 \
    --show-standard-json-input > json-input.std.json