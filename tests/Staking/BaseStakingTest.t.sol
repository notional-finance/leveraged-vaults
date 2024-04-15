// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseAcceptanceTest.sol";
import "./harness/BaseStakingHarness.sol";
import "@deployments/Deployments.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";
import "@contracts/proxy/nProxy.sol";
import "@interfaces/trading/ITradingModule.sol";

abstract contract BaseStakingTest is BaseAcceptanceTest {

    function deployTestVault() internal override returns (IStrategyVault) {
        (address impl, /* */) = harness.deployVaultImplementation();
        nProxy proxy;

        if (harness.EXISTING_DEPLOYMENT() != address(0)) {
            proxy = nProxy(payable(harness.EXISTING_DEPLOYMENT()));
            vm.prank(Deployments.NOTIONAL.owner());
            UUPSUpgradeable(harness.EXISTING_DEPLOYMENT()).upgradeTo(impl);
        } else {
            bytes memory initData = harness.getInitializeData();

            vm.prank(Deployments.NOTIONAL.owner());
            proxy = new nProxy(address(impl), initData);
        }

        BaseStakingVault p = BaseStakingVault(payable(address(proxy)));
        // TODO: will this work for all vaults? maybe not we need to do some internal
        // accounting sometimes?
        totalVaultSharesAllMaturities = IERC20(p.STAKING_TOKEN()).balanceOf(address(p));

        (address[] memory t, address[] memory oracles) = harness.getRequiredOracles();
        for (uint256 i; i < t.length; i++) {
            (AggregatorV2V3Interface oracle, /* */) = Deployments.TRADING_MODULE.priceOracles(t[i]);
            if (address(oracle) == address(0)) {
                vm.prank(Deployments.NOTIONAL.owner());
                Deployments.TRADING_MODULE.setPriceOracle(t[i], AggregatorV2V3Interface(oracles[i]));
            } else {
                require(address(oracle) == oracles[i], "Oracle Mismatch");
            }
        }

        return IStrategyVault(address(proxy));
    }

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal pure override returns (bytes memory) {
        // TODO: need to update this for the boolean deposit params
        return abi.encode("");
    }

    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        RedeemParams memory r;

        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        r.minPurchaseAmount = 0;
        r.dexId = m.primaryDexId;
        r.exchangeData = m.exchangeData;

        return abi.encode(r);
    }

    function v() internal view returns (BaseStakingVault) {
        return BaseStakingVault(payable(address(vault)));
    }

    function checkInvariants() internal override {
        uint256 stakingTokens = IERC20(v().STAKING_TOKEN()).balanceOf(address(vault));
        assertEq(
            totalVaultSharesAllMaturities,
            stakingTokens * uint256(Constants.INTERNAL_TOKEN_PRECISION) / v().STAKING_PRECISION(),
            "Total Vault Shares"
        );
    }

    /** Entry Tests **/
    function test_ShortCircuitOnZeroDeposit() public {
        address account = makeAddr("account");
        vm.expectCall(address(Deployments.NOTIONAL), "", 0);
        uint256 vaultShares = enterVaultBypass(account, 0, maturities[1], "");
        assertEq(vaultShares, 0);
    }

    // test_RevertIf_accountEntry_hasAccountWithdraw()
    // test_RevertIf_accountEntry_hasForcedWithdraw()
    // test_RevertIf_borrowAgainstTokens_InsufficientCollateral()
    // test_borrowAgainstTokens()

    /** Exit Tests **/
    function test_ShortCircuitOnZeroRedeem() public {
        address account = makeAddr("account");
        vm.expectCall(address(Deployments.NOTIONAL), "", 0);
        uint256 amount = exitVaultBypass(account, 0, maturities[1], "");
        assertEq(amount, 0);
    }

    function test_RevertIf_ExitTradeSlippageFails() public {
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        bytes memory params = getDepositParams(depositAmount, maturity);
        uint256 vaultShares = enterVault(account, depositAmount, maturity, params);

        RedeemParams memory r;
        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        r.minPurchaseAmount = 100e18;
        r.dexId = m.primaryDexId;
        r.exchangeData = m.exchangeData;

        vm.roll(5);
        vm.warp(block.timestamp + 3600);

        vm.expectRevert(TradeFailed.selector);
        exitVaultBypass(account, vaultShares, maturity, abi.encode(r));
    }

    /** Withdraw Tests **/

    // test_forceWithdraw_changeToAccountValue()
    // test_accountWithdraw_changeToAccountValue()

    /** Liquidate Tests **/


    // test_RevertIf_liquidate_accountInsolvent()
    // test_RevertIf_liquidate_accountCollateralDecrease()
    // test_RevertIf_overRedeem_activeWithdraws()
    // test_RevertIf_redeemWithdraw_incorrectVaultShares()

    // test_finalizeWithdrawsOutOfBand()

    // test_liquidate_borrowAgainstWithdrawRequest()
    // test_liquidate_splitWithdrawRequest()

    /** Helper Methods **/

    function _assertWithdrawRequestIsEmpty(WithdrawRequest memory w) internal {
        assertEq(w.requestId, 0, "requestId should be 0");
        assertEq(w.vaultShares, 0, "vaultShares should be 0");
        assertTrue(!w.hasSplit, "hasSplit should be false");
    }

    function _forceWithdraw(address account, bool expectRevert, bytes memory error) internal {
        address admin = makeAddr("admin");
        vm.startPrank(Deployments.NOTIONAL.owner());
        v().grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.stopPrank();

        vm.startPrank(admin);
        if (expectRevert) {
            vm.expectRevert(error);
        }
        v().forceWithdraw(account);
        vm.stopPrank();
    }

    function _forceWithdraw(address account) internal {
        _forceWithdraw(account, false, "");
    }

}