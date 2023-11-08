// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseComposablePoolVault.sol";

abstract contract BaseBalancerComposable_wstETHcbETHrETH is BaseComposablePoolVault {
    function setUp() public override virtual {
        // BAL
        rewardToken = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
        rewardPool = IAuraRewardPool(0x8cA64Bd82AbFE138E195ce5Cb7268CA285D42245);
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 50
        });

        // NOTE: includes BPT token
        numTokens = 4;
        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_wstETH_wstETHcbETHrETH is BaseBalancerComposable_wstETHcbETHrETH {
    function setUp() public override { primaryBorrowCurrency = WSTETH; super.setUp(); }
}

contract Test_cbETH_wstETHcbETHrETH is BaseBalancerComposable_wstETHcbETHrETH {
    function setUp() public override { primaryBorrowCurrency = CBETH; super.setUp(); }
}

contract Test_rETH_wstETHcbETHrETH is BaseBalancerComposable_wstETHcbETHrETH {
    function setUp() public override {
        primaryBorrowCurrency = RETH; 
        super.setUp();

        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 100 * BASIS_POINT;
    }
}