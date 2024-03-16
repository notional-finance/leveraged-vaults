#!/bin/bash
set -e

source .env

# Check if exactly two arguments are provided
if [ $# -lt 3 ]; then
    echo "Usage: $0 CHAIN PROTOCOL POOL_NAME TOKEN"
    echo "  --upgrade only deploys a new implementation"
    echo "  --update  creates config update json"
    exit 1
fi

# Assign arguments to named variables
CHAIN=$1
PROTOCOL=$2
POOL_NAME=$3
TOKEN=$4

UPGRADE_VAULT=false
UPDATE_CONFIG=false
# Loop through all command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade)
      UPGRADE_VAULT=true
      ;;
    --update)
      UPDATE_CONFIG=true
      ;;
  esac
  shift
done

export FOUNDRY_PROFILE=$CHAIN
export UPGRADE_VAULT=$UPGRADE_VAULT
export UPDATE_CONFIG=$UPDATE_CONFIG
RPC_VAR="$(echo "$CHAIN"_RPC_URL | tr '[:lower:]' '[:upper:]')"
export RPC_URL="${!RPC_VAR}"

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

process_json_file() {
    local input_file="$1"

    # Process the JSON file using jq
    jq 'walk(if type == "number" then tostring else . end)' "$input_file" > temp.json && mv temp.json "$input_file"
}


CONTRACT=""
CONTRACT_PATH=""
# Switch statement for contract verification
case "$PROTOCOL" in
    "Convex")
        CONTRACT="Curve2TokenConvexVault"
        CONTRACT_PATH="vaults/curve"
        ;;
    "Aura")
        CONTRACT="BalancerComposableAuraVault"
        CONTRACT_PATH="vaults/balancer"
        ;;
esac

CHAIN_ID=""
case "$CHAIN" in
    "mainnet")
        CHAIN_ID=1
        ;;
    "arbitrum")
        CHAIN_ID=42161
        ;;
esac

forge build --force
FILE_NAME=SingleSidedLP_${PROTOCOL}_${POOL_NAME}
forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
    -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
   --chain $CHAIN_ID --account ARBITRUM-ONE_DEPLOYER -vvvv

VAULT_CODE=`jq '.transactions[0].transaction.data' broadcast/$FILE_NAME.t.sol/$CHAIN_ID/dry-run/run-latest.json | tr -d '"'`
IMPLEMENTATION_ADDRESS=`jq '.transactions[0].contractAddress' broadcast/$FILE_NAME.t.sol/$CHAIN_ID/dry-run/run-latest.json | tr -d '"'`

echo "Expected Implementation Address: $IMPLEMENTATION_ADDRESS"
print_constructor_args $VAULT_CODE 448

confirm "Do you want to proceed?" || exit 0

# NOTE: if this fails on estimating gas when executing the deployment we have to manually
# send the transaction. Verification will not be required if the code has not changed.
cast send --account ARBITRUM-ONE_DEPLOYER --chain $CHAIN_ID  --gas-limit 120935302 --gas-price 0.1gwei --create $VAULT_CODE

# Requires manual verification
forge verify-contract $IMPLEMENTATION_ADDRESS \
    contracts/$CONTRACT_PATH/$CONTRACT.sol:$CONTRACT -c $CHAIN \
    --show-standard-json-input > json-input.std.json

if [ "$UPGRADE_VAULT" = true ]; then
  echo "Vault Implementation Deployed to $IMPLEMENTATION_ADDRESS"
  PROXY=$(jq --arg network "$CHAIN" \
          --arg protocol "$PROTOCOL" \
          --arg pair "[$TOKEN]:$POOL_NAME" \
          -r '.[$network][$protocol][$pair]' "vaults.json")
  process_json_file "scripts/deploy/$PROXY.upgradeVault.json"
  exit 0
fi

# Create the proxy contract
echo "Deploying Proxy contract for $IMPLEMENTATION_ADDRESS"
confirm "Do you want to proceed?" || exit 0

# TODO: need to read the proxy address from the json file
forge create contracts/proxy/nProxy.sol:nProxy \
    --verify --gas-limit 120935302 --gas-price 0.1gwei \
    --chain $CHAIN_ID --account ARBITRUM-ONE_DEPLOYER --legacy --json \
    --constructor-args $IMPLEMENTATION_ADDRESS "" | tee proxy.json

# export PROXY="0x431dbfE3050eA39abBfF3E0d86109FB5BafA28fD"

# Re-run this to generate the gnosis outputs
forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
    -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
    --gas-limit 1125899906842624 --chain $CHAIN_ID --account ARBITRUM-ONE_DEPLOYER

process_json_file "scripts/deploy/$PROXY.initVault.json"
process_json_file "scripts/deploy/$PROXY.updateConfig.json"

# Generate Emergency Exit
jq --arg chain "$CHAIN" \
   --arg protocol "$PROTOCOL" \
   --arg pair "[$TOKEN]:$POOL_NAME" \
   --arg addr "$PROXY" \
   '.[$chain][$protocol][$pair] = $addr' vaults.json > tmp.json && mv tmp.json vaults.json

source venv/bin/activate
brownie run scripts/generateEmergencyExit.py --network arbitrum-one