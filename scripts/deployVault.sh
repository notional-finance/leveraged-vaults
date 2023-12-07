#!/bin/bash
set -e

export FOUNDRY_PROFILE=deployment
export UPGRADE_VAULT=false
export UPDATE_CONFIG=true

source .env
forge script tests/SingleSidedLP/pools/USDC_DAI_USDT_USDC_e.t.sol:Test_USDC \
    -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
    --gas-limit 1125899906842624 --chain 42161 --account ARBITRUM-ONE_DEPLOYER --broadcast --verify

# NOTE: if this fails on estimating gas when executing the deployment we have to manually
# send the transaction. Verification will not be required if the code has not changed.
# cast send --account ARBITRUM-ONE_DEPLOYER --chain 42161  --gas-limit 120935302 --gas-price 0.1gwei --create \

# forge verify-contract 0x740a42dB721F2118b472C419D49c6A627079B469 \
#     contracts/vaults/BalancerComposableAuraVault.sol:BalancerComposableAuraVault -c 42161 \
#     --show-standard-json-input > json-input.std.json