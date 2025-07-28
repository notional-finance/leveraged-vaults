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
jq --arg chain "$CHAIN" \
   --arg protocol "$PROTOCOL" \
   --arg pair "[$TOKEN]:$POOL_NAME" \
   --arg addr "$PROXY" \
   '.[$chain][$protocol][$pair] = $addr' vaults.json > tmp.json && mv tmp.json vaults.json

source venv/bin/activate
brownie run scripts/generateEmergencyExit.py --network $CHAIN