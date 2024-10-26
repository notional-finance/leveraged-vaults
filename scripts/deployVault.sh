#!/bin/bash
set -e

source .env

# Check if exactly two arguments are provided
if [ $# -lt 4 ]; then
    echo "Usage: $0 CHAIN PROTOCOL POOL_NAME TOKEN"
    echo "  --execute  executes the deployment, otherwise only does a dry run"
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
EXECUTE=false
# Loop through all command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade)
      UPGRADE_VAULT=true
      ;;
    --update)
      UPDATE_CONFIG=true
      ;;
    --execute)
      EXECUTE=true
      ;;
  esac
  shift
done

export FOUNDRY_PROFILE=$CHAIN
export UPGRADE_VAULT=$UPGRADE_VAULT
export UPDATE_CONFIG=$UPDATE_CONFIG
RPC_VAR="$(echo "$CHAIN"_RPC_URL | tr '[:lower:]' '[:upper:]')"
export ETH_RPC_URL="${!RPC_VAR}"

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


FILE_NAME=""
# Switch statement for contract verification
case "$PROTOCOL" in
    "Aura" | "Convex" | "Balancer" | "Curve")
        FILE_NAME="SingleSidedLP"_${PROTOCOL}_${POOL_NAME}
        ;;
    "Pendle")
        FILE_NAME="PendlePT_${POOL_NAME}_${TOKEN}"
        ;;
esac

CHAIN_ID=""
VERIFIER_URL=""
case "$CHAIN" in
    "mainnet")
        CHAIN_ID=1
        VERIFIER_URL="https://api.etherscan.io/api"
        ;;
    "arbitrum")
        CHAIN_ID=42161
        export ETHERSCAN_API_KEY=$ARBISCAN_API_KEY
        VERIFIER_URL="https://api.arbiscan.io/api"
        ;;
esac

DEPLOYER=MAINNET_V2_DEPLOYER
DEPLOYER_ADDRESS=`cast wallet address --account $DEPLOYER`

forge build

OUTPUT_FILE=""
if [ "$EXECUTE" = true ]; then
    echo "Deploying Vault Implementation for $FILE_NAME on $CHAIN"
    forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
        -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS \
        --chain $CHAIN_ID --account $DEPLOYER \
        --verify --verifier-url $VERIFIER_URL --etherscan-api-key $ETHERSCAN_API_KEY \
        --slow --broadcast
    OUTPUT_FILE="broadcast/$FILE_NAME.t.sol/$CHAIN_ID/run-latest.json"

else 
    echo "Dry Run: Deploying Vault Implementation for $FILE_NAME on $CHAIN"
    forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
        -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS \
        --chain $CHAIN_ID --account $DEPLOYER
    OUTPUT_FILE="broadcast/$FILE_NAME.t.sol/$CHAIN_ID/dry-run/run-latest.json"
fi

IMPLEMENTATION_ADDRESS=`jq '.transactions[0].contractAddress' $OUTPUT_FILE | tr -d '"'`

if [ "$PROTOCOL" = "Pendle" ]; then
    PENDLE_ORACLE_ADDRESS=`jq '.transactions[1].contractAddress' $OUTPUT_FILE | tr -d '"'`
    echo "Pendle Oracle Deployed to $PENDLE_ORACLE_ADDRESS"
fi

if [ "$UPGRADE_VAULT" = true ]; then
  echo "Vault Implementation Deployed to $IMPLEMENTATION_ADDRESS"
  PROXY=$(jq --arg network "$CHAIN" \
          --arg protocol "$PROTOCOL" \
          --arg pair "[$TOKEN]:$POOL_NAME" \
          -r '.[$network][$protocol][$pair]' "vaults.json")
  process_json_file "scripts/deploy/$PROXY.upgradeVault.json"
  exit 0
fi

if [ "$EXECUTE" = false ]; then exit 0; fi

# Create the proxy contract
echo "Deploying Proxy contract for $IMPLEMENTATION_ADDRESS"
confirm "Do you want to proceed?" || exit 0

forge create contracts/proxy/nProxy.sol:nProxy \
    --verify --chain $CHAIN_ID --account $DEPLOYER --legacy --json \
    --constructor-args $IMPLEMENTATION_ADDRESS "0x" | tee proxy.json

export PROXY=`head -n 1 proxy.json | jq '.deployedTo' | tr -d '"'`
rm proxy.json

# Re-run this to generate the gnosis outputs
forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
    -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS --chain $CHAIN_ID 

process_json_file "scripts/deploy/$PROXY.initVault.json"
process_json_file "scripts/deploy/$PROXY.updateConfig.json"

# Generate Emergency Exit
jq --arg chain "$CHAIN" \
   --arg protocol "$PROTOCOL" \
   --arg pair "[$TOKEN]:$POOL_NAME" \
   --arg addr "$PROXY" \
   '.[$chain][$protocol][$pair] = $addr' vaults.json > tmp.json && mv tmp.json vaults.json

source venv/bin/activate
brownie run scripts/generateEmergencyExit.py --network $CHAIN