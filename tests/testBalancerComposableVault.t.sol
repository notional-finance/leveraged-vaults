// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseComposablePoolVault.sol";

abstract contract BaseBalancerComposable_wstETHcbETHrETH is BaseComposablePoolVault {
    function setUp() public override virtual {
        rewardPool = IAuraRewardPool(0x8cA64Bd82AbFE138E195ce5Cb7268CA285D42245);
        settings = StrategyVaultSettings({
            emergencySettlementSlippageLimitPercent: 1,
            maxPoolShare: 20,
            oraclePriceDeviationLimitPercent: 50,
            poolSlippageLimitPercent: 50
        });

        // NOTE: includes BPT token
        numTokens = 4;
        // TODO: handle zero deposit values?
        minDeposit = 0.001e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }

    // test_RevertIf_oracleDeviationIsTrue_entry_exit()
    // test_RevertIf_aboveMaxPoolShare()
    // test_rewardReinvestment()
    // test_Exit_withSecondaryTrades()
    // test_Enter_withSecondaryTrades()
    // test_ReentrancyContext
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