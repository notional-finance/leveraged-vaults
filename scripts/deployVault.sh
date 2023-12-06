#!/bin/bash
set -e

export FOUNDRY_PROFILE=deployment
source .env
forge script tests/SingleSidedLP/pools/USDC_DAI_USDT_USDC_e.t.sol:Test_USDC \
    -f $RPC_URL --sender 0x8F5ea3CDe898B208280c0e93F3aDaaf1F5c35a7e