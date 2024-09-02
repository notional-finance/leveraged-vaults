#!/bin/bash
source .env

export CHAIN_ID=mainnet

export FOUNDRY_PROFILE=$CHAIN_ID
export DEPLOYER=MAINNET_V2_DEPLOYER
RPC_VAR="$(echo "$CHAIN_ID"_RPC_URL | tr '[:lower:]' '[:upper:]')"
export ETH_RPC_URL="${!RPC_VAR}"
export DEPLOYER_ADDRESS=`cast wallet address --account $DEPLOYER`

forge build --force
forge script scripts/deploy/DeployTradingModule.s.sol:DeployTradingModule \
     -f $ETH_RPC_URL --sender $DEPLOYER_ADDRESS --account $DEPLOYER --verify --broadcast \
     --etherscan-api-key $ETHERSCAN_API_KEY
     # --verifier-url https://api.arbiscan.io/api --etherscan-api-key $ARBISCAN_API_KEY
