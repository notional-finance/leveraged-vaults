#!/bin/bash
set -e

source .env

# Check if exactly five arguments are provided
if [ $# -ne 5 ]; then
    echo "Usage: $0 CHAIN PROTOCOL POOL_NAME TOKEN PROXY"
    exit 1
fi

# Assign arguments to named variables
CHAIN=$1
PROTOCOL=$2
POOL_NAME=$3
TOKEN=$4
PROXY=$5

export PROXY=$PROXY
export FOUNDRY_PROFILE=$CHAIN
RPC_VAR="$(echo "$CHAIN"_RPC_URL | tr '[:lower:]' '[:upper:]')"
export ETH_RPC_URL="${!RPC_VAR}"

DEPLOYER=DEPLOYER
DEPLOYER_ADDRESS=`cast wallet address --account $DEPLOYER`

# Determine the FILE_NAME based on protocol
case "$PROTOCOL" in
    "Aura" | "Convex" | "Balancer" | "Curve")
        FILE_NAME="SingleSidedLP"_${PROTOCOL}_${POOL_NAME}
        ;;
    "Pendle")
        FILE_NAME="PendlePT_${POOL_NAME}_${TOKEN}"
        ;;
esac

# Get chain ID
case "$CHAIN" in
    "mainnet")
        CHAIN_ID=1
        ;;
    "arbitrum")
        CHAIN_ID=42161
        ;;
esac


export INIT_VAULT=true
# Run the specific forge script command
forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
    -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS --chain $CHAIN_ID