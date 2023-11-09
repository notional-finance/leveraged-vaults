// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract wstETH_WETH is BaseComposablePool {
    function setUp() public override virtual {
        rewardPool = IERC20(0xa7BdaD177D474f946f3cDEB4bcea9d24Cf017471);
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
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_wstETH is wstETH_WETH {
    function setUp() public override { primaryBorrowCurrency = WSTETH; super.setUp(); }
}

contract Test_WETH is wstETH_WETH {
    function setUp() public override { primaryBorrowCurrency = ETH; super.setUp(); }
}