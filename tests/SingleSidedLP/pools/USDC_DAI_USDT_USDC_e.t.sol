// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract USDC_DAI_USDT_USDC_e is BaseComposablePool {
    function setUp() public override virtual {
        rewardPool = IERC20(0x416C7Ad55080aB8e294beAd9B8857266E3B3F28E);
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 10 * BASIS_POINT;
        maxRelExitValuation = 10 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_USDC is USDC_DAI_USDT_USDC_e {
    function setUp() public override { 
        primaryBorrowCurrency = USDC;
        super.setUp();

        minDeposit = 0.01e6;
        maxDeposit = 100_000e6;
    }
}

contract Test_DAI is USDC_DAI_USDT_USDC_e {
    function setUp() public override { 
        primaryBorrowCurrency = DAI;
        super.setUp();

        minDeposit = 0.01e18;
        maxDeposit = 100_000e18;
    }
}

contract Test_USDT is USDC_DAI_USDT_USDC_e {
    function setUp() public override { 
        primaryBorrowCurrency = USDT;
        super.setUp();

        minDeposit = 0.01e6;
        maxDeposit = 100_000e6;
    }
}
