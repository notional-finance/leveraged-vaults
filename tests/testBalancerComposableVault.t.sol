// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseComposablePoolVault.sol";

contract TestBalancerComposable_wstETH_wstETHcbETHrETH is BaseComposablePoolVault {
    function setUp() public override {
        primaryBorrowCurrency = WSTETH;
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

}
