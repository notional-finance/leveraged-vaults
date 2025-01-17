#!/bin/bash
set -e

source .env

CHAIN='mainnet'
FILE_NAME='PendlePT_sUSDe_28MAY2025_USDC'
ETH_RPC_URL='https://eth-mainnet.g.alchemy.com/v2/pq08EwFvymYFPbDReObtP-SFw3bCes8Z'
DEPLOYER_ADDRESS='0x9299B176bFd1CaBB967ac2A027814FAad8782BA7'
CHAIN_ID=1
export PROXY=0xBeee4C0993B1336b2Cf971F48960D8DE92dEe4A4
export UPDATE_CONFIG=true
# Re-run this to generate the gnosis outputs
forge script tests/generated/${CHAIN}/${FILE_NAME}.t.sol:Deploy_${FILE_NAME} \
    -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS --chain $CHAIN_ID 
