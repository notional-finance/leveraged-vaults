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

    function test_RevertIf_accountEntry_hasWithdraw(uint8 maturityIndex, bool useForce) public {
        address account = makeAddr("account");
        maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account,
            maxDeposit,
            maturity,
            getDepositParams(maxDeposit, maturity)
        );

        if (useForce) {
            _forceWithdraw(account);
        } else {
            vm.prank(account);
            v().initiateWithdraw(vaultShares);
        }

        // Cannot enter the vault again because a withdraw is in process
        expectRevert_enterVault(account, maxDeposit, maturity, getDepositParams(maxDeposit, maturity), "");
    }

    // TODO: these tests are up in the air, not sure if we should support this feature, it could allow
    // an account to maximize their leverage while they cannot be liquidated due to restrictions we put
    // on their account.
    // test_liquidate_borrowAgainstWithdrawRequest()
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

    function test_exitVault_hasWithdrawRequest_tradeShares(
        uint8 maturityIndex, uint256 withdrawPercent
    ) public {
        vm.assume(0 < withdrawPercent && withdrawPercent < 80);
        address account = makeAddr("account");
        maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account,
            maxDeposit,
            maturity,
            getDepositParams(maxDeposit, maturity)
        );

        vm.roll(5);
        vm.warp(block.timestamp + 3600);
        uint256 sharesForWithdraw = vaultShares * withdrawPercent / 100;

        // Initiate a withdraw for up to 70% of the shares.
        vm.prank(account);
        v().initiateWithdraw(sharesForWithdraw);

        uint256 remainingShares = vaultShares - sharesForWithdraw;
        console.log(vaultShares, sharesForWithdraw, remainingShares);

        vm.prank(account);

        // Should fail because insufficient liquid shares
        bytes memory params = getRedeemParams(remainingShares + 1, maturity);
        vm.expectRevert("Insufficient Shares");
        vm.prank(account);
        Deployments.NOTIONAL.exitVault(
            account, address(vault), account, remainingShares + 1, 0, 0, params
        );

        uint256 lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * 
                -1 * int256(remainingShares) / int256(vaultShares)
        );
        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);

        params = getRedeemParams(remainingShares, maturity);
        vm.prank(account);
        Deployments.NOTIONAL.exitVault(
            account, address(vault), account, remainingShares, lendAmount, 0, params
        );

        // Assert that the vault shares remaining are just in the withdraw request now
        assertTrue(w.requestId != 0);
        assertEq(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).vaultShares,
            w.vaultShares
        );
        assertFalse(w.hasSplit);
        _assertWithdrawRequestIsEmpty(f);
    }

    function test_exitVault_useWithdrawRequest(
        uint8 maturityIndex, uint256 depositAmount, uint256 withdrawPercent, bool useForce
    ) public {
        vm.assume(0 <= withdrawPercent && withdrawPercent <= 100);
        if (withdrawPercent == 0) useForce = true;
        if (withdrawPercent == 100) useForce = false;

        address account = makeAddr("account");

        uint256 vaultShares;
        {
            maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
            uint256 maturity = maturities[maturityIndex];
            depositAmount =  bound(depositAmount, 5 * minDeposit, maxDeposit);

            vaultShares = enterVault(
                account,
                depositAmount,
                maturity,
                getDepositParams(depositAmount, maturity)
            );
        }

        vm.warp(block.timestamp + 3600);

        uint256 shareForRedeem = useForce ? vaultShares : vaultShares * withdrawPercent / 100;
        uint256 lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * -1
        );
        lendAmount = useForce ? lendAmount : lendAmount * withdrawPercent / 100;

        vm.prank(account);
        // should fail if withdraw is not initiated
        vm.expectRevert();
        Deployments.NOTIONAL.exitVault(
            account, address(vault), account, vaultShares, lendAmount, 0, ""
        );

        vm.prank(account);
        if (withdrawPercent > 0) {
            v().initiateWithdraw(vaultShares * withdrawPercent / 100);
        }
        if (useForce) {
            _forceWithdraw(account);
        }
        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);


        vm.prank(account);
        // should fail if withdraw is not finalized
        vm.expectRevert();
        Deployments.NOTIONAL.exitVault(
            account, address(vault), account, shareForRedeem, lendAmount, 0, ""
        );

        finalizeWithdrawRequest(account);

        vm.prank(account);
        vm.expectRevert();
        // should fail if exact amount of shares is not specified
        Deployments.NOTIONAL.exitVault(
            account, address(vault), account, shareForRedeem - 1, lendAmount, 0, ""
        );

        vm.prank(account);
        uint256 totalToReceiver = Deployments.NOTIONAL.exitVault(
            account, address(vault), account, shareForRedeem, lendAmount, 0, ""
        );

        uint256 maxDiff;
        if (maturityIndex == 0) {
            maxDiff = 1e14; // 0.01 %
        } else {
            maxDiff = 7e15; // 0.7%
        }
        assertApproxEqRel(totalToReceiver, useForce ? depositAmount : depositAmount * withdrawPercent / 100, maxDiff, "1");

        (f, w) = v().getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(w);
        _assertWithdrawRequestIsEmpty(f);
    }

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
    function test_RevertIf_deleverageAccount_isInsolvent(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        enterVaultLiquidation(account, maturity);

        _changeCollateralRatio(500);
        (VaultAccountHealthFactors memory healthBefore, /* */, /* */) = Deployments.NOTIONAL.getVaultAccountHealthFactors(
            account, address(vault)
        );
        assertLt(healthBefore.collateralRatio, 0);

        address liquidator = makeAddr("liquidator");
        uint256 value = 100 ether;
        deal(liquidator, value);
        vm.prank(liquidator);
        vm.expectRevert("Insolvent");
        v().deleverageAccount{value: value}(account, address(v()), liquidator, 0, int256(value / 1e10));
    }

    function test_RevertIf_deleverageAccount_collateralDecrease(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        enterVaultLiquidation(account, maturity);

        // TODO: need to try to find the right value per vault here...
        _changeCollateralRatio(930);

        address liquidator = makeAddr("liquidator");
        uint256 value = 100 ether;
        deal(liquidator, value);
        vm.prank(liquidator);
        vm.expectRevert("Collateral Decrease");
        v().deleverageAccount{value: value}(account, address(v()), liquidator, 0, int256(value / 1e10));
    }

    function test_deleverageAccount_noWithdrawRequest(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVaultLiquidation(account, maturity);

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

    function test_deleverageAccount_hasLiquidShares(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVaultLiquidation(account, maturity);

        uint256 vaultSharesForWithdraw = vaultShares / 500;
        vm.prank(account);
        v().initiateWithdraw(vaultSharesForWithdraw);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(v()));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(v()));

        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0, "11");
        assertEq(w.vaultShares, vaultSharesForWithdraw, "22");
        assertEq(w.hasSplit, false, "33");
        _assertWithdrawRequestIsEmpty(f);
    }

    function test_deleverageAccount_splitAccountWithdrawRequest(
        uint8 maturityIndex, uint8 withdrawPercent
    ) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        withdrawPercent = uint8(bound(withdrawPercent, 95, 100));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVaultLiquidation(account, maturity);

        uint256 vaultSharesForWithdraw = vaultShares * withdrawPercent / 100;
        vm.prank(account);
        v().initiateWithdraw(vaultSharesForWithdraw);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(v()));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(v()));


        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        uint256 splitVaultShares = liquidatedAmount - (vaultShares - vaultSharesForWithdraw);
        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0, "11");
        assertEq(w.vaultShares, vaultSharesForWithdraw - splitVaultShares, "22");
        assertEq(w.hasSplit, true, "33");
        _assertWithdrawRequestIsEmpty(f);

        (SplitWithdrawRequest memory s) = v().getSplitWithdrawRequest(w.requestId);

        assertEq(s.totalVaultShares, vaultSharesForWithdraw, "7");
        assertEq(s.finalized, false, "8");
    }

    function test_deleverageAccount_splitAccountWithdrawRequest_hasForceWithdraw(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        VaultConfig memory c = Deployments.NOTIONAL.getVaultConfig(address(vault));
        // TODO: if you increase this collateral ratio then we can withdraw fewer vault
        // shares in order to complete the liquidation
        // TODO: alternatively we can decrease the deleverage collateral ratio in the
        // vault config
        uint256 cr = uint256(c.minCollateralRatio) + 10 * maxRelEntryValuation;
        uint256 vaultShares = enterVaultLiquidation(account, maturity, cr);

        // This has to be a pretty high portion or the liquidation will fail due to insufficient
        // vault shares in the withdraw
        uint256 vaultSharesForWithdraw = vaultShares * 999 / 1000;
        vm.prank(account);
        v().initiateWithdraw(vaultSharesForWithdraw);

        _forceWithdraw(account);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(v()));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(v()));

        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0, "1");
        assertEq(w.vaultShares, vaultSharesForWithdraw - liquidatedAmount, "2");
        assertEq(w.hasSplit, true, "3");
        assertTrue(f.requestId != 0, "4");
        assertEq(f.vaultShares, vaultShares - vaultSharesForWithdraw, "5");
        assertEq(f.hasSplit, false, "6");

        (WithdrawRequest memory lf, WithdrawRequest memory lw) = v().getWithdrawRequests(liquidator);

        assertTrue(lw.requestId != 0, "11");
        assertEq(lw.vaultShares, liquidatedAmount, "22");
        assertEq(lw.hasSplit, true, "33");
        _assertWithdrawRequestIsEmpty(lf);

        (SplitWithdrawRequest memory s) = v().getSplitWithdrawRequest(w.requestId);
        assertEq(s.totalVaultShares, vaultSharesForWithdraw, "7");
        assertEq(s.finalized, false, "8");
    }

    function test_deleverageAccount_splitForceWithdrawRequest(uint8 maturityIndex, uint256 withdrawPercent) public {
        withdrawPercent = uint256(bound(withdrawPercent, 0, 5));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVaultLiquidation(account, maturity);

        // NOTE: this is based on 1000 denominator so that we have sufficient forced shares to liquidate
        uint256 vaultSharesForWithdraw = vaultShares * withdrawPercent / 1000;
        if (vaultSharesForWithdraw != 0) {
            vm.prank(account);
            v().initiateWithdraw(vaultSharesForWithdraw);
        }

        _forceWithdraw(account);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(v()));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(v()));

        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);
        // withdraw request should be unchanged after liquidation
        if (withdrawPercent == 0) {
            assertEq(w.requestId, 0, "1-true");
        } else {
            assertTrue(w.requestId != 0, "1-false");
        }
        assertEq(w.vaultShares, vaultSharesForWithdraw, "2");
        assertEq(w.hasSplit, false, "3");
        assertTrue(f.requestId != 0, "4");
        assertEq(f.vaultShares, (vaultShares - vaultSharesForWithdraw) - liquidatedAmount, "5");
        assertEq(f.hasSplit, true, "6");

        (WithdrawRequest memory lf, WithdrawRequest memory lw) = v().getWithdrawRequests(liquidator);
        assertTrue(lw.requestId != 0, "11");
        assertEq(lw.vaultShares, liquidatedAmount, "22");
        assertEq(lw.hasSplit, true, "33");
        _assertWithdrawRequestIsEmpty(lf);

        (SplitWithdrawRequest memory s) = v().getSplitWithdrawRequest(f.requestId);
        assertEq(s.totalVaultShares,  vaultShares - vaultSharesForWithdraw, "7");
        assertEq(s.finalized, false, "8");
    }

    function test_finalizeWithdrawsManual(
        uint8 maturityIndex, uint256 depositAmount, uint256 withdrawPercent, bool useForce
    ) public {
        vm.assume(0 <= withdrawPercent && withdrawPercent <= 100);
        if (withdrawPercent == 0) useForce = true;
        if (withdrawPercent == 100) useForce = false;

        address account = makeAddr("account");

        uint256 vaultShares;
        uint256 positionValue;
        {
            maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
            uint256 maturity = maturities[maturityIndex];
            depositAmount =  bound(depositAmount, 8 * minDeposit, maxDeposit);

            vaultShares = enterVault(
                account,
                depositAmount,
                maturity,
                getDepositParams(depositAmount, maturity)
            );
            positionValue = uint256(v().convertStrategyToUnderlying(account, vaultShares, maturity));
        }
        vm.warp(block.timestamp + 3600);

        // uint256 shareForRedeem = useForce ? vaultShares :  vaultShares * withdrawPercent / 100;
        uint256 lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * -1
        );
        lendAmount = useForce ? lendAmount : lendAmount * withdrawPercent / 100;

        vm.prank(account);
        if (withdrawPercent > 0) {
            v().initiateWithdraw(vaultShares * withdrawPercent / 100);
        }
        if (useForce) {
            _forceWithdraw(account);
        }
        (WithdrawRequest memory f, WithdrawRequest memory w) = v().getWithdrawRequests(account);

        {
            finalizeWithdrawRequest(account);

            vm.prank(account);
            v().finalizeWithdrawsManual(account);

            (f, w) = v().getWithdrawRequests(account);
        }

        if (f.requestId != 0) {
            SplitWithdrawRequest memory s = v().getSplitWithdrawRequest(f.requestId);
            assertTrue(f.vaultShares != 0, "1");
            assertTrue(f.hasSplit, "2");
            assertEq(f.vaultShares, s.totalVaultShares);
            assertTrue(s.finalized, "3");
            assertGe(s.totalWithdraw, positionValue - positionValue * withdrawPercent / 100, "4");
        }
        if (w.requestId != 0) {
            SplitWithdrawRequest memory s = v().getSplitWithdrawRequest(w.requestId);
            assertTrue(w.vaultShares != 0, "5");
            assertTrue(w.hasSplit, "6");
            assertEq(w.vaultShares, s.totalVaultShares);
            assertTrue(s.finalized, "7");
            assertGe(s.totalWithdraw, positionValue * withdrawPercent / 100, "8");
        }

        vm.prank(account);

        uint256 maxDiff;
        if (maturityIndex == 0) {
            maxDiff = 1e14; // 0.01 %
        } else {
            maxDiff = 7e15; // 0.7%
        }
        // exit vault and check that account received expected amount
        assertApproxEqRel(
            Deployments.NOTIONAL.exitVault(
                account, address(vault), account, useForce ? vaultShares :  vaultShares * withdrawPercent / 100, lendAmount, 0, ""
            ),
            useForce ? depositAmount : depositAmount * withdrawPercent / 100,
            maxDiff,
            "9"
        );

        (f, w) = v().getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(w);
        _assertWithdrawRequestIsEmpty(f);
    }

    /** Helper Methods **/
    function _changeCollateralRatio() internal override {
        _changeCollateralRatio(960);
    }

    function _changeCollateralRatio(int256 discount) internal {
        address token = v().STAKING_TOKEN();
        (AggregatorV2V3Interface oracle, /* */) = Deployments.TRADING_MODULE.priceOracles(token);
        MockOracle mock = new MockOracle();
        mock.setAnswer(oracle.latestAnswer() * discount / 1000);

        setPriceOracle(token, address(mock));
    }

    function _liquidateAccount(address account) internal returns (address liquidator) {
        _changeCollateralRatio();

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

    function finalizeWithdrawRequest(address account) internal virtual;
}