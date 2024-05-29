#!/bin/bash
source .env

export CHAIN_ID=arbitrum

export FOUNDRY_PROFILE=$CHAIN_ID
export DEPLOYER=MAINNET_V2_DEPLOYER
RPC_VAR="$(echo "$CHAIN_ID"_RPC_URL | tr '[:lower:]' '[:upper:]')"
export ETH_RPC_URL="${!RPC_VAR}"
export DEPLOYER_ADDRESS=`cast wallet address --account $DEPLOYER`
export NUM_LIQUIDATORS=2

forge script scripts/deploy/DeployFlashLiquidator.s.sol:DeployFlashLiquidator \
     -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS --account $DEPLOYER --verify --broadcast \
     --verifier-url https://api.arbiscan.io/api --etherscan-api-key $ARBISCAN_API_KEY

# Arbitrum Liquidators
# 0xA44a8729d139b39A322a9c7754fAe98B6cff6C71
# 0x53423Db7ac663Aa1941a809A6D787bfFc7A5C8A9
# 0x0158fC072Ff5DDE8F7b9E2D00e8782093db888Db