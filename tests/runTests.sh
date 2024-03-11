#!/bin/bash
source .env
python tests/SingleSidedLP/generate_tests.py

export RPC_URL=$MAINNET_RPC_URL
export FORK_BLOCK=19364776
forge test --mp "tests/generated/mainnet/Test_SingleSidedLP_Convex_xUSDT_crvUSD.t.sol" --mt RewardReinvestment -vvvv
# forge test --mp "tests/generated/mainnet/**"

# export RPC_URL=$ARBITRUM_RPC_URL
# export FORK_BLOCK=176730531
# forge test --mp "tests/generated/arbitrum/**"

# forge test --mp "tests/testFlashLiquidator.t.sol"
# forge test --mp "tests/testTradingModule.t.sol"