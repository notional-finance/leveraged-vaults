source .env
python tests/SingleSidedLP/generate_tests.py

# Check if exactly two arguments are provided
if [ $# -ne 4 ]; then
    echo "Usage: $0 CHAIN PROTOCOL POOL_NAME TOKEN"
    exit 1
fi

process_json_file() {
    local input_file="$1"

    # Process the JSON file using jq
    jq 'walk(if type == "number" then tostring else . end)' "$input_file" > temp.json && mv temp.json "$input_file"
}

# Assign arguments to named variables
CHAIN=$1
PROTOCOL=$2
POOL_NAME=$3
TOKEN=$4

PROXY=$(jq --arg network "$CHAIN" \
           --arg protocol "$PROTOCOL" \
           --arg pair "[$TOKEN]:$POOL_NAME" \
           -r '.[$network][$protocol][$pair]' "vaults.json")



CHAIN_ID=""
case "$CHAIN" in
    "mainnet")
        CHAIN_ID=1
        ;;
    "arbitrum")
        CHAIN_ID=42161
        export ETHERSCAN_API_KEY=$ARBISCAN_API_KEY
        ;;
esac

export UPDATE_CONFIG=true
export FOUNDRY_PROFILE=$CHAIN
RPC_VAR="$(echo "$CHAIN"_RPC_URL | tr '[:lower:]' '[:upper:]')"
export ETH_RPC_URL="${!RPC_VAR}"

# Deployer address is not used in the script
DEPLOYER_ADDRESS="0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"

echo "Updating Config at Proxy Address:" $PROXY
FILE_NAME=SingleSidedLP_${PROTOCOL}_${POOL_NAME}
# Re-run this to generate the gnosis outputs
forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
    -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS --chain $CHAIN_ID

process_json_file "scripts/deploy/$PROXY.updateConfig.json"
