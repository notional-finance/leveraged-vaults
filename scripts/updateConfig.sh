export FOUNDRY_PROFILE=deployment
export UPDATE_CONFIG=true

CHAIN=42161

# Check if exactly two arguments are provided
if [ $# -ne 3 ]; then
    echo "Usage: $0 PROTOCOL POOL_NAME TOKEN"
    exit 1
fi

process_json_file() {
    local input_file="$1"

    # Process the JSON file using jq
    jq 'walk(if type == "number" then tostring else . end)' "$input_file" > temp.json && mv temp.json "$input_file"
}

# Assign arguments to named variables
PROTOCOL=$1
POOL_NAME=$2
TOKEN=$3

PROXY=$(jq --arg network "$CHAIN" \
           --arg protocol "$PROTOCOL" \
           --arg pair "[$TOKEN]:$POOL_NAME" \
           -r '.[$network][$protocol][$pair]' "vaults.json")


source .env

echo "Updating Config at Proxy Address:" $PROXY
# Re-run this to generate the gnosis outputs
forge script tests/SingleSidedLP/pools/$PROTOCOL/$POOL_NAME.t.sol:Test_$TOKEN \
    -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e \
    --gas-limit 1125899906842624 --chain $CHAIN --account ARBITRUM-ONE_DEPLOYER

process_json_file "scripts/deploy/$PROXY.updateConfig.json"
