// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import "@interfaces/ethena/IsUSDe.sol";

contract Test_Staking_Ethena_xUSDC is BaseStakingTest {

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        return abi.encode(DepositParams({
            dexId: m.primaryDexId, // Curve
            minPurchaseAmount: 0,
            exchangeData: m.exchangeData
        }));
    }

    function setUp() public override {
        // MakerDAO PSM
        WHALE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        harness = new Harness_Staking_Ethena_xUSDC();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 1_000e6;
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

contract Harness_Staking_Ethena_xUSDC is EthenaStakingHarness { }

contract Deploy_Staking_Ethena_xUSDC is Harness_Staking_Ethena_xUSDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_Staking_Ethena_xUSDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}
