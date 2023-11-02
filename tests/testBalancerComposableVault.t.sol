// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseComposablePoolVault.sol";

contract TestBalancerComposable_wstETH_wstETHcbETHrETH is BaseComposablePoolVault {
    function setUp() public override {
        primaryBorrowCurrency = WSTETH;
        balancerPoolId = 0x4a2f6ae7f3e5d715689530873ec35593dc28951b000000000000000000000481;
        rewardPool = IAuraRewardPool(0x8cA64Bd82AbFE138E195ce5Cb7268CA285D42245);
        settings = StrategyVaultSettings({
            emergencySettlementSlippageLimitPercent: 1,
            maxPoolShare: 20,
            oraclePriceDeviationLimitPercent: 1,
            poolSlippageLimitPercent: 1
        });
        super.setUp();
    }

    function checkInvariants() internal override { }
}
