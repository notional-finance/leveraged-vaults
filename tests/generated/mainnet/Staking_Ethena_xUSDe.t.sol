// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import "@interfaces/ethena/IsUSDe.sol";

contract Test_Staking_Ethena_xUSDe is BaseStakingTest {
    function setUp() public override {
        harness = new Harness_Staking_Ethena_xUSDe();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 10e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }

    function finalizeWithdrawRequest(address account) internal override {
        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);
        IsUSDe.UserCooldown memory fCooldown = sUSDe.cooldowns(address(uint160(f.requestId)));
        IsUSDe.UserCooldown memory wCooldown = sUSDe.cooldowns(address(uint160(w.requestId)));

        uint256 maxCooldown = fCooldown.cooldownEnd > wCooldown.cooldownEnd ?
            fCooldown.cooldownEnd : wCooldown.cooldownEnd;

        vm.warp(maxCooldown);
    }
}

contract Harness_Staking_Ethena_xUSDe is EthenaStakingHarness { }

contract Deploy_Staking_Ethena_xUSDe is Harness_Staking_Ethena_xUSDe, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_Staking_Ethena_xUSDe();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}
