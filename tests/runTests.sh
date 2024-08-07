#!/bin/bash
source .env
source venv/bin/activate
python tests/SingleSidedLP/generate_tests.py

export RPC_URL=$MAINNET_RPC_URL
export FORK_BLOCK=19626900
export FOUNDRY_PROFILE=mainnet
forge test --mp "tests/generated/mainnet/*"

export RPC_URL=$ARBITRUM_RPC_URL
export FORK_BLOCK=199952636
export FOUNDRY_PROFILE=arbitrum
forge test --mp "tests/generated/arbitrum/**"

forge test --mp "tests/testTradingModule.t.sol"