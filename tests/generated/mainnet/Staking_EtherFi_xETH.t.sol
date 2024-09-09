// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import {WithdrawRequestNFT} from "@contracts/vaults/staking/protocols/EtherFi.sol";

contract Test_Staking_EtherFi_xETH is BaseStakingTest {
    function setUp() public override {
        harness = new Harness_Staking_EtherFi_xETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 10e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        maxRelExitValuation_WithdrawRequest_Fixed = 0.03e18;
        maxRelExitValuation_WithdrawRequest_Variable = 0.005e18;
        deleverageCollateralDecreaseRatio = 925;
        defaultLiquidationDiscount = 955;
        withdrawLiquidationDiscount = 955;
        splitWithdrawPriceDecrease = 610;

        super.setUp();
    }

    function finalizeWithdrawRequest(address account) internal override {
        WithdrawRequest memory w = v().getWithdrawRequest(account);

        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705); // etherFi: admin
        WithdrawRequestNFT.finalizeRequests(w.requestId);
    }
}

contract Harness_Staking_EtherFi_xETH is EtherFiStakingHarness { }

contract Deploy_Staking_EtherFi_xETH is Harness_Staking_EtherFi_xETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_Staking_EtherFi_xETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}
