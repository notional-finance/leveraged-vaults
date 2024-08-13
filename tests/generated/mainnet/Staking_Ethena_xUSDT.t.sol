// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";
import "@interfaces/ethena/IsUSDe.sol";

contract Test_Staking_Ethena_xUSDT is BaseStakingTest {

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        return abi.encode(DepositParams({
            dexId: m.primaryDexId,
            minPurchaseAmount: 0,
            exchangeData: m.exchangeData
        }));
    }

    function getRedeemParamsWithdrawRequest(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal override view returns (bytes memory) {
        RedeemParams memory r;

        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        r.minPurchaseAmount = 0;
        r.dexId = m.primaryDexId;
        // USDe/USDT pool is 0.01% fee range
        r.exchangeData = abi.encode(UniV3Adapter.UniV3SingleData({
            fee: 100
        }));

        return abi.encode(r);
    }

    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        RedeemParams memory r;

        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        r.minPurchaseAmount = 0;
        r.dexId = m.primaryDexId;
        // sUSDe/USDT pool is 0.05% fee range
        r.exchangeData = abi.encode(UniV3Adapter.UniV3SingleData({
            fee: 500
        }));

        return abi.encode(r);
    }

    function setUp() public override {
        harness = new Harness_Staking_Ethena_xUSDC();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 1_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        maxRelExitValuation_WithdrawRequest_Fixed = 0.03e18;
        maxRelExitValuation_WithdrawRequest_Variable = 0.01e18;
        deleverageCollateralDecreaseRatio = 925;
        defaultLiquidationDiscount = 952;
        withdrawLiquidationDiscount = 952;
        splitWithdrawPriceDecrease = 610;

        super.setUp();
    }

    function finalizeWithdrawRequest(address account) internal override {
        WithdrawRequest memory w = v().getWithdrawRequest(account);
        IsUSDe.UserCooldown memory wCooldown = sUSDe.cooldowns(address(uint160(w.requestId)));

        setMaxOracleFreshness();
        vm.warp(wCooldown.cooldownEnd);
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
