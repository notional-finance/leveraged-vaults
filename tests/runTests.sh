#!/bin/bash
# Exits immediately if a test fails
set -e

source .env
export PYTHONPATH=$PYTHONPATH:$(pwd)
source venv/bin/activate
python tests/SingleSidedLP/generate_tests.py
python tests/Staking/generate_tests.py

# Check if a command line argument is provided
if [ $# -ge 1 ]; then
    # Extract the network from the provided path
    network=$(echo $1 | cut -d'/' -f3)
    
    # Set the appropriate RPC_URL and FORK_BLOCK based on the network
    case $network in
        mainnet)
            export RPC_URL=$MAINNET_RPC_URL
            export FORK_BLOCK=19691163
            ;;
        arbitrum)
            export RPC_URL=$ARBITRUM_RPC_URL
            export FORK_BLOCK=199952636
            ;;
        *)
            echo "Unknown network: $network"
            exit 1
            ;;
    esac
    
    # Set the FOUNDRY_PROFILE
    export FOUNDRY_PROFILE=$network
    
    # Run forge test with the provided path
    if [ $# -eq 2 ]; then
        forge test --mp "$1" --mt "$2" -vvv
    else
        forge test --mp "$1" -vv
    fi
    
    # Exit after running the specific test
    exit 0
fi

# If no argument is provided, continue with the existing commands
export RPC_URL=$MAINNET_RPC_URL
export FORK_BLOCK=19691163
export FOUNDRY_PROFILE=mainnet
forge test --mp "tests/generated/mainnet/**"

export RPC_URL=$ARBITRUM_RPC_URL
export FORK_BLOCK=199952636
export FOUNDRY_PROFILE=arbitrum
forge test --mp "tests/generated/arbitrum/**"

forge test --mp "tests/testTradingModule.t.sol"