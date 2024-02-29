#!/bin/bash
source .env
python tests/SingleSidedLP/generate_tests.py

export RPC_URL=$ARBITRUM_RPC_URL
export FORK_BLOCK=$ARBITRUM_FORK_BLOCK
forge test --mp "tests/generated/arbitrum/**"

export RPC_URL=$MAINNET_RPC_URL
export FORK_BLOCK=$MAINNET_FORK_BLOCK
forge test --mp "tests/generated/mainnet/**"

forge test --mp "tests/*.t.sol"