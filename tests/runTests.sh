#!/bin/bash
source .env
export PYTHONPATH=$PYTHONPATH:$(pwd)
python tests/SingleSidedLP/generate_tests.py
python tests/Staking/generate_tests.py

forge build

# export RPC_URL=$MAINNET_RPC_URL
# export FORK_BLOCK=19691163
# export FOUNDRY_PROFILE=mainnet
# # forge test --mp "tests/generated/mainnet/**"
# forge test --mp "tests/generated/mainnet/Staking_*.t.sol"

# export RPC_URL=$ARBITRUM_RPC_URL
# export FORK_BLOCK=221089505
# export FOUNDRY_PROFILE=arbitrum
# forge test --mp "tests/generated/arbitrum/Staking_*.t.sol"
# forge test --mp "tests/generated/arbitrum/**"

# forge test --mp "tests/testTradingModule.t.sol"