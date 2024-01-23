#!/bin/bash
set -e

export FOUNDRY_PROFILE=deployment
export UPGRADE_VAULT=false
export UPDATE_CONFIG=true

# Check if exactly two arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 POOL_NAME TOKEN"
    exit 1
fi

# Assign arguments to named variables
POOL_NAME=$1
TOKEN=$2

# Function to prompt for confirmation
confirm() {
    read -p "$1 (y/n): " response
    case "$response" in
        [yY]|[yY][eE][sS]) 
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# Function to get the last 448 characters of the string,
# split into 64-character chunks, and print the last 40 characters of each chunk
print_constructor_args() {
    local full_string="$1"
    local length="$2"
    local last_chars="${full_string: -$length}"
    local segment_length=64
    local last_chars_length=40

    # Iterate over the last 448 characters, split into 64-character chunks, and print the last 40 characters
    for ((i = 0; i < ${#last_chars}; i += segment_length)); do
        local chunk="${last_chars:i:segment_length}"
        echo "0x${chunk: -last_chars_length}"
    done
}


source .env
forge script tests/SingleSidedLP/pools/$POOL_NAME.t.sol:Test_$TOKEN \
    -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
    --gas-limit 1125899906842624 --chain 42161 --account ARBITRUM-ONE_DEPLOYER

# VAULT_CODE=`jq '.transactions[0].transaction.data' broadcast/$POOL_NAME.t.sol/42161/dry-run/run-latest.json | tr -d '"'`
# IMPLEMENTATION_ADDRSES=`jq '.transactions[0].contractAddress' broadcast/$POOL_NAME.t.sol/42161/dry-run/run-latest.json | tr -d '"'`

# echo "Expected Implementation Address: $IMPLEMENTATION_ADDRSES"
# print_constructor_args $VAULT_CODE 448

# confirm "Do you want to proceed?" || exit 0

# # NOTE: if this fails on estimating gas when executing the deployment we have to manually
# # send the transaction. Verification will not be required if the code has not changed.
# cast send --account ARBITRUM-ONE_DEPLOYER --chain 42161  --gas-limit 120935302 --gas-price 0.1gwei --create $VAULT_CODE

# forge verify-contract $IMPLEMENTATION_ADDRSES \
#     contracts/vaults/BalancerComposableAuraVault.sol:BalancerComposableAuraVault -c 42161 \
#     --show-standard-json-input > json-input.std.json

# PROXY_CODE=`jq '.transactions[0].transaction.data' broadcast/$POOL_NAME.t.sol/42161/dry-run/run-latest.json | tr -d '"'`
# PROXY_ADDRESS=`jq '.transactions[0].contractAddress' broadcast/$POOL_NAME.t.sol/42161/dry-run/run-latest.json | tr -d '"'`

# echo "Expected Implementation Address: $PROXY_ADDRESS"
# print_constructor_args $PROXY_CODE 192

# # Example usage
# confirm "Do you want to proceed?" || exit 0

# cast send --account ARBITRUM-ONE_DEPLOYER --chain 42161  --gas-limit 120935302 --gas-price 0.1gwei --create $PROXY_CODE

# FILE=scripts/deploy/0x37dD23Ab1885982F789A2D6400B583B8aE09223d.initVault.json
# jq 'walk(if type == "number" then tostring else . end)' $FILE > temp.json && mv temp.json $FILE

