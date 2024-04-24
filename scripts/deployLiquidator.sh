#!/bin/bash
source .env

export RPC_URL=$ARBITRUM_RPC_URL
export FOUNDRY_PROFILE=arbitrum
export CHAIN_ID=42161
export DEPLOYER=MAINNET_V2_DEPLOYER
export DEPLOYER_ADDRESS=`cast wallet address --account $DEPLOYER`

forge build --force
forge script scripts/deploy/DeployFlashLiquidator.s.sol:DeployFlashLiquidator \
     -f $RPC_URL --sender $DEPLOYER_ADDRESS --account $DEPLOYER --verify --broadcast