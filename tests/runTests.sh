#!/bin/bash
source .env
python tests/SingleSidedLP/generate_tests.py

export RPC_URL=$MAINNET_RPC_URL
export FORK_BLOCK=19675503
export FOUNDRY_PROFILE=mainnet
# forge test --mp "tests/generated/mainnet/**"
forge test --mp "tests/generated/mainnet/Staking_PendlePT_EtherFi.t.sol" -vv

# export RPC_URL=$ARBITRUM_RPC_URL
# export FORK_BLOCK=194820300
# export FOUNDRY_PROFILE=arbitrum
# forge test --mp "tests/generated/arbitrum/**"

# forge test --mp "tests/testTradingModule.t.sol --mt test_exitVault_useWithdrawRequest -vvv"