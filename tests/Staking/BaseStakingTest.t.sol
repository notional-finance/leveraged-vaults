// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../MockOracle.sol";
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
                setPriceOracle(t[i], oracles[i]);
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

    function test_valuation(uint256 depositAmount, uint8 maturityIndex) public {
        address account = makeAddr("account");
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        (int256 rate, /* int256 rateDecimals */) = Deployments.TRADING_MODULE.getOraclePrice(
            v().STAKING_TOKEN(), address(primaryBorrowToken)
        );

        assertEq(
            uint256(v().convertStrategyToUnderlying(account, vaultShares, maturity)),
            vaultShares * uint256(rate) / uint256(Constants.INTERNAL_TOKEN_PRECISION)
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

    // test_RevertIf_overRedeem_activeWithdraws()
    // test_RevertIf_redeemWithdraw_incorrectVaultShares()

    /** Withdraw Tests **/
    function test_RevertIf_accountWithdraw_insufficientShares() public {
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        uint256 vaultShares =
            enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

        address accountWithNoShares = makeAddr("noShareAddress");

        vm.prank(accountWithNoShares);
        vm.expectRevert();
        v().initiateWithdraw(0);

        vm.prank(accountWithNoShares);
        vm.expectRevert();
        v().initiateWithdraw(vaultShares);
    }

    function test_RevertIf_accountWithdraw_unauthorizedAccount() public {
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        uint256 vaultShares =
            enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

        vm.startPrank(makeAddr("unauthorized account"));
        vm.expectRevert();
        v().initiateWithdraw(vaultShares);
    }

    function test_accountWithdraw(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        withdrawPercent = uint8(bound(withdrawPercent, 1, 100));
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        (
            WithdrawRequest memory f,
            WithdrawRequest memory w
        ) = v().getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(f);
        _assertWithdrawRequestIsEmpty(w);
        int256 valueBefore = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        uint256 vaultShareToWithdraw = vaultShares * withdrawPercent / 100;
        vm.startPrank(account);
        v().initiateWithdraw(vaultShareToWithdraw);
        vm.stopPrank();
        int256 valueAfter = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        (f, w) = v().getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(f);
        assertTrue(w.requestId != 0);
        assertEq(w.vaultShares, vaultShareToWithdraw);
        assertEq(w.hasSplit, false);

        // Assert no change to valuation
        assertApproxEqAbs(valueBefore, valueAfter, roundingPrecision, "Valuation Change");
    }

    function test_RevertIf_accountWithdraw_hasExistingRequest(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent, uint8 secondWithdrawPercent
    ) public {
        vm.assume(0 < withdrawPercent && withdrawPercent < 100);
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        vm.prank(account);
        v().initiateWithdraw(vaultShares * withdrawPercent / 100);

        secondWithdrawPercent = uint8(bound(secondWithdrawPercent, 1, 100 - withdrawPercent));
        vm.prank(account);
        vm.expectRevert("Existing Request");
        v().initiateWithdraw(vaultShares * secondWithdrawPercent / 100);
    }

    function test_forceWithdraw(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        withdrawPercent = uint8(bound(withdrawPercent, 0, 99));
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );
        int256 valueBefore = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        uint256 vaultShareToWithdraw = vaultShares * withdrawPercent / 100;

        (
            WithdrawRequest memory f,
            WithdrawRequest memory w
        ) = v().getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(f);

        // Only initiate the withdraw if we are withdrawing any shares
        if (vaultShareToWithdraw > 0) {
            vm.prank(account);
            v().initiateWithdraw(vaultShareToWithdraw);
            (f, w) = v().getWithdrawRequests(account);
            assertTrue(w.requestId != 0, "4");
            assertEq(w.vaultShares, vaultShareToWithdraw, "5");
            assertEq(w.hasSplit, false, "6");
        }

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        v().forceWithdraw(account);

        (f, w) = v().getWithdrawRequests(account);
        assertTrue(f.requestId != 0, "7");
        assertEq(f.vaultShares, vaultShares - vaultShareToWithdraw, "8");
        assertEq(f.hasSplit, false, "9");
        if (vaultShareToWithdraw > 0) {
            assertTrue(w.requestId != 0, "10");
        }

        assertEq(w.vaultShares, vaultShareToWithdraw, "11");
        assertEq(w.hasSplit, false, "12");

        int256 valueAfter = v().convertStrategyToUnderlying(account, vaultShares, maturity);
        // Assert no change to valuation
        assertApproxEqAbs(valueBefore, valueAfter, roundingPrecision, "Valuation Change");
    }

    function test_RevertIf_forceWithdraw_accountInitiatesWithdraw(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        withdrawPercent = uint8(bound(withdrawPercent, 1, 100));
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        uint256 maturity = maturities[maturityIndex];
        address account = makeAddr("account");

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        v().forceWithdraw(account);


        vm.prank(account);
        vm.expectRevert("Existing Request");
        v().initiateWithdraw(vaultShares * withdrawPercent / 100);
    }

    function test_forceWithdraw_initiateNewWithdraw(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");

        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );
        int256 valueBefore = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        v().forceWithdraw(account);
        (
            WithdrawRequest memory f,
            WithdrawRequest memory w
        ) = v().getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(w);
        assertTrue(f.requestId != 0, "4");
        assertEq(f.vaultShares, vaultShares, "5");
        assertEq(f.hasSplit, false, "6");
        int256 valueAfter = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        // Assert no change to valuation
        assertApproxEqAbs(valueBefore, valueAfter, roundingPrecision, "Valuation Change");
    }

    function test_RevertIf_forceWithdraw_secondForceWithdraw(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        _forceWithdraw(account);
        _forceWithdraw({ account: account, expectRevert: true, error: "Existing Request" });
    }

    /** Liquidate Tests **/

    function test_deleverageAccount_noWithdrawRequest(uint8 maturityIndex, uint256 depositAmount) public {
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(v()));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(v()));

        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);
        // should not have initiated withdraw request
        _assertWithdrawRequestIsEmpty(w);
        _assertWithdrawRequestIsEmpty(f);
    }

    // test_RevertIf_liquidate_accountInsolvent()
    // test_RevertIf_liquidate_accountCollateralDecrease()
    // test_finalizeWithdrawsOutOfBand()
    // test_liquidate_borrowAgainstWithdrawRequest()
    // test_liquidate_splitWithdrawRequest()

    /** Helper Methods **/

    function _liquidateAccount(address account) internal returns (address liquidator) {
        address token = v().STAKING_TOKEN();
        (AggregatorV2V3Interface oracle, /* */) = Deployments.TRADING_MODULE.priceOracles(token);
        MockOracle mock = new MockOracle();
        mock.setAnswer(oracle.latestAnswer() * 57 / 100);

        setPriceOracle(token, address(mock));

        liquidator = makeAddr("liquidator");
        uint256 value = 100 ether;
        deal(liquidator, value);
        vm.prank(liquidator);
        v().deleverageAccount{value: value}(account, address(v()), liquidator, 0, int256(value / 1e10));
    }

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