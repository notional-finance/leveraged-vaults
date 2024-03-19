#!/bin/bash
source .env
python tests/SingleSidedLP/generate_tests.py

export RPC_URL=$MAINNET_RPC_URL
export FORK_BLOCK=19469130
export FOUNDRY_PROFILE=mainnet
forge build --force
forge test --mp "tests/generated/mainnet/**"

export RPC_URL=$ARBITRUM_RPC_URL
export FORK_BLOCK=191743200
export FOUNDRY_PROFILE=arbitrum
forge build --force
forge test --mp "tests/generated/arbitrum/**"

forge test --mp "tests/testFlashLiquidator.t.sol"
forge test --mp "tests/testTradingModule.t.sol"