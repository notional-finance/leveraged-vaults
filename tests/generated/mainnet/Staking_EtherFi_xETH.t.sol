// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";

contract Test_Staking_EtherFi_xETH is BaseStakingTest {
    function setUp() public override {
        harness = new Harness_Staking_EtherFi_xETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 10e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_Staking_EtherFi_xETH is EtherFiStakingHarness { }

contract Deploy_SingleSidedLP_Convex_xUSDT_crvUSD is Harness_Staking_EtherFi_xETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_Staking_EtherFi_xETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}
