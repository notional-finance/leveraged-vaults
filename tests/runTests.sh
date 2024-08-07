#!/bin/bash
# Exits immediately if a test fails
set -e

source .env
export PYTHONPATH=$PYTHONPATH:$(pwd)
python tests/SingleSidedLP/generate_tests.py
python tests/Staking/generate_tests.py

export RPC_URL=$MAINNET_RPC_URL
export FORK_BLOCK=19691163
export FOUNDRY_PROFILE=mainnet
forge test --mp "tests/generated/mainnet/**"

export RPC_URL=$ARBITRUM_RPC_URL
export FORK_BLOCK=194820300
export FOUNDRY_PROFILE=arbitrum
forge test --mp "tests/generated/arbitrum/**"

forge test --mp "tests/testTradingModule.t.sol"