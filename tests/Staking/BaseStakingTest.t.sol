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
    uint256 maxRelExitValuation_WithdrawRequest_Fixed;
    uint256 maxRelExitValuation_WithdrawRequest_Variable;
    int256 deleverageCollateralDecreaseRatio;
    int256 defaultLiquidationDiscount;
    int256 withdrawLiquidationDiscount;

    function deployTestVault() internal override returns (IStrategyVault) {
        (address impl, /* */) = harness.deployVaultImplementation();
        nProxy proxy;

        address existingDeployment = harness.EXISTING_DEPLOYMENT();
        if (existingDeployment != address(0)) {
            proxy = nProxy(payable(existingDeployment));
            vm.prank(Deployments.NOTIONAL.owner());
            UUPSUpgradeable(existingDeployment).upgradeTo(impl);
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
    ) internal view virtual override returns (bytes memory) {
        return abi.encode("");
    }

    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view virtual override returns (bytes memory) {
        RedeemParams memory r;

        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        r.minPurchaseAmount = 0;
        r.dexId = m.primaryDexId;
        r.exchangeData = m.exchangeData;

        return abi.encode(r);
    }

    function hasWithdrawRequests() internal view returns (bool) {
        StakingMetadata memory m = BaseStakingHarness(address(harness)).getMetadata();
        return m.hasWithdrawRequests;
    }

    function getRedeemParamsWithdrawRequest(
        uint256 vaultShares,
        uint256 maturity
    ) internal view virtual returns (bytes memory) {
        return getRedeemParams(vaultShares, maturity);
    }

    function v() internal view returns (BaseStakingVault) {
        return BaseStakingVault(payable(address(vault)));
    }

    function checkInvariants() internal override {
        uint256 stakingTokens = IERC20(v().STAKING_TOKEN()).balanceOf(address(vault));
        uint256 stakingPrecision = 10 ** IERC20(v().STAKING_TOKEN()).decimals();
        assertEq(
            totalVaultSharesAllMaturities,
            stakingTokens * uint256(Constants.INTERNAL_TOKEN_PRECISION) / stakingPrecision,
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
            (vaultShares * uint256(rate) * precision) / (uint256(Constants.INTERNAL_TOKEN_PRECISION) * 1e18)
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
        vm.skip(!hasWithdrawRequests());

        address account = makeAddr("account");
        maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
        uint256 maturity = maturities[maturityIndex];

        enterVault(
            account,
            maxDeposit,
            maturity,
            getDepositParams(maxDeposit, maturity)
        );

        if (useForce) {
            _forceWithdraw(account);
        } else {
            vm.prank(account);
            v().initiateWithdraw();
        }

        // Cannot enter the vault again because a withdraw is in process
        expectRevert_enterVault(account, maxDeposit, maturity, getDepositParams(maxDeposit, maturity), "");
    }

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

    function test_exitVault_useWithdrawRequest(
        uint8 maturityIndex, uint256 depositAmount, bool useForce
    ) public {
        vm.skip(!hasWithdrawRequests());
        address account = makeAddr("account");

        uint256 vaultShares;
        uint256 maturity;
        {
            maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
            maturity = maturities[maturityIndex];
            depositAmount =  bound(depositAmount, 5 * minDeposit, maxDeposit);

            vaultShares = enterVault(
                account,
                depositAmount,
                maturity,
                getDepositParams(depositAmount, maturity)
            );
        }

        vm.warp(block.timestamp + 3600);

        uint256 lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * -1
        );
        // Use max uint on variable lending to clear the position
        lendAmount = maturityIndex == 0 ? type(uint256).max : lendAmount;

        if (useForce) {
            _forceWithdraw(account);
        } else {
            vm.prank(account);
            v().initiateWithdraw();
        }

        bytes memory params = getRedeemParamsWithdrawRequest(vaultShares, maturity);
        vm.prank(account);
        // should fail if withdraw is not finalized
        vm.expectRevert();
        Deployments.NOTIONAL.exitVault(
            account, address(vault), account, vaultShares, lendAmount, 0, params
        );

        finalizeWithdrawRequest(account);

        vm.prank(account);
        vm.expectRevert();
        // should fail if exact amount of shares is not specified
        Deployments.NOTIONAL.exitVault(
            account, address(vault), account, vaultShares - 1, lendAmount, 0, params
        );

        vm.prank(account);
        uint256 totalToReceiver = Deployments.NOTIONAL.exitVault(
            account, address(vault), account, vaultShares, lendAmount, 0, params
        );

        uint256 maxDiff;
        if (maturityIndex == 0) {
            maxDiff = maxRelExitValuation_WithdrawRequest_Variable;
        } else {
            maxDiff = maxRelExitValuation_WithdrawRequest_Fixed;
        }
        assertApproxEqRel(totalToReceiver, depositAmount, maxDiff, "1");

        _assertWithdrawRequestIsEmpty(v().getWithdrawRequest(account));
    }

    /** Withdraw Tests **/
    function test_RevertIf_accountWithdraw_insufficientShares() public {
        vm.skip(!hasWithdrawRequests());
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

        address accountWithNoShares = makeAddr("noShareAddress");

        vm.prank(accountWithNoShares);
        vm.expectRevert();
        v().initiateWithdraw();

        vm.prank(accountWithNoShares);
        vm.expectRevert();
        v().initiateWithdraw();
    }

    function test_RevertIf_accountWithdraw_unauthorizedAccount() public {
        vm.skip(!hasWithdrawRequests());
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

        vm.startPrank(makeAddr("unauthorized account"));
        vm.expectRevert();
        v().initiateWithdraw();
    }

    function test_accountWithdraw(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        vm.skip(!hasWithdrawRequests());
        withdrawPercent = uint8(bound(withdrawPercent, 1, 100));
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        WithdrawRequest memory w = v().getWithdrawRequest(account);
        _assertWithdrawRequestIsEmpty(w);
        int256 valueBefore = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        vm.startPrank(account);
        v().initiateWithdraw();
        vm.stopPrank();
        int256 valueAfter = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        w = v().getWithdrawRequest(account);
        assertTrue(w.requestId != 0);
        assertEq(w.vaultShares, vaultShares);
        assertEq(w.hasSplit, false);

        // Assert no change to valuation
        assertApproxEqRel(valueBefore, valueAfter, 0.002e18, "Valuation Change");
    }

    function test_RevertIf_accountWithdraw_hasExistingRequest(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        vm.skip(!hasWithdrawRequests());
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

        vm.prank(account);
        v().initiateWithdraw();

        vm.prank(account);
        vm.expectRevert("Existing Request");
        v().initiateWithdraw();
    }

    function test_forceWithdraw(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        vm.skip(!hasWithdrawRequests());
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];

        uint256 vaultShares = enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );
        int256 valueBefore = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        WithdrawRequest memory w = v().getWithdrawRequest(account);
        _assertWithdrawRequestIsEmpty(w);

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        v().forceWithdraw(account);

        w = v().getWithdrawRequest(account);
        assertTrue(w.requestId != 0, "7");
        assertEq(w.vaultShares, vaultShares, "8");
        assertEq(w.hasSplit, false, "9");

        int256 valueAfter = v().convertStrategyToUnderlying(account, vaultShares, maturity);
        // Assert no change to valuation
        assertApproxEqRel(valueBefore, valueAfter, 0.003e18, "Valuation Change");
    }

    function test_RevertIf_forceWithdraw_accountInitiatesWithdraw(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        vm.skip(!hasWithdrawRequests());
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        uint256 maturity = maturities[maturityIndex];
        address account = makeAddr("account");

        enterVault(
            account, depositAmount, maturity, getDepositParams(depositAmount, maturity)
        );

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        v().grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        v().forceWithdraw(account);


        vm.prank(account);
        vm.expectRevert("Existing Request");
        v().initiateWithdraw();
    }

    function test_forceWithdraw_initiateNewWithdraw(
        uint8 maturityIndex, uint256 depositAmount, bool forceFinalizeWithdraw
    ) public {
        vm.skip(!hasWithdrawRequests());
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
        if (forceFinalizeWithdraw) finalizeWithdrawRequest(account);
        WithdrawRequest memory f = v().getWithdrawRequest(account);
        assertTrue(f.requestId != 0, "4");
        assertEq(f.vaultShares, vaultShares, "5");
        assertEq(f.hasSplit, false, "6");
        int256 valueAfter = v().convertStrategyToUnderlying(account, vaultShares, maturity);

        // Assert no change to valuation
        assertApproxEqRel(valueBefore, valueAfter, 0.003e18, "Valuation Change");
    }

    function test_RevertIf_forceWithdraw_secondForceWithdraw(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        vm.skip(!hasWithdrawRequests());
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

    function test_RevertIf_accountWithdraw_insufficientCollateral(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        vm.skip(!hasWithdrawRequests());
        depositAmount = uint256(bound(depositAmount, minDeposit, maxDeposit));
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVaultLiquidation(account, maturity);

        _changeCollateralRatio();
        // attempt to account withdraw
        vm.prank(account);
        vm.expectRevert("Insufficient Collateral");
        v().initiateWithdraw();

        _forceWithdraw(account);
        WithdrawRequest memory w = v().getWithdrawRequest(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0);
        assertEq(w.vaultShares, vaultShares);
    }

    // /** Liquidate Tests **/
    function test_RevertIf_deleverageAccount_isInsolvent(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        enterVaultLiquidation(account, maturity);

        _changeTokenPrice(500, v().STAKING_TOKEN());
        (
            VaultAccountHealthFactors memory healthBefore,
            int256[3] memory maxDeposit,
            /* */
        ) = Deployments.NOTIONAL.getVaultAccountHealthFactors(account, address(vault));
        assertLt(healthBefore.collateralRatio, 0);

        address liquidator = makeAddr("liquidator");
        uint256 maxDepositExternal = uint256(maxDeposit[0]) * precision / 1e8;
        dealTokensAndApproveNotional(maxDepositExternal * 2, liquidator);
        uint256 msgValue = address(primaryBorrowToken) == Constants.ETH_ADDRESS ? maxDepositExternal  : 0;
        vm.prank(liquidator);
        vm.expectRevert("Insolvent");
        v().deleverageAccount{value: msgValue}(account, address(v()), liquidator, 0, maxDeposit[0]);
    }

    function test_RevertIf_deleverageAccount_collateralDecrease(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        enterVaultLiquidation(account, maturity);

        _changeTokenPrice(deleverageCollateralDecreaseRatio, v().STAKING_TOKEN());

        (/* */, int256[3] memory maxDeposit, /* */) = Deployments.NOTIONAL.getVaultAccountHealthFactors(
            account, address(vault)
        );
        address liquidator = makeAddr("liquidator");

        uint256 maxDepositExternal = uint256(maxDeposit[0]) * precision / 1e8;
        dealTokensAndApproveNotional(maxDepositExternal * 2, liquidator);
        uint256 msgValue = address(primaryBorrowToken) == Constants.ETH_ADDRESS ? maxDepositExternal  : 0;
        vm.prank(liquidator);
        vm.expectRevert("Collateral Decrease");
        v().deleverageAccount{value: msgValue}(account, address(v()), liquidator, 0, maxDeposit[0]);
    }

    function test_deleverageAccount_noWithdrawRequest(uint8 maturityIndex) public {
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVaultLiquidation(account, maturity);

        _changeCollateralRatio();
        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(v()));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(v()));

        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        // should not have initiated withdraw request
        _assertWithdrawRequestIsEmpty(v().getWithdrawRequest(account));
    }

    function test_deleverageAccount_splitAccountWithdrawRequest(
        uint8 maturityIndex
    ) public virtual {
        vm.skip(!hasWithdrawRequests());
        maturityIndex = uint8(bound(maturityIndex, 0, 2));
        address account = makeAddr("account");
        uint256 maturity = maturities[maturityIndex];
        uint256 vaultShares = enterVaultLiquidation(account, maturity);

        vm.prank(account);
        v().initiateWithdraw();

        _changeTokenPrice(
            withdrawLiquidationDiscount,
            BaseStakingHarness(address(harness)).withdrawToken(address(v()))
        );
        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(v()));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(v()));

        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        WithdrawRequest memory w = v().getWithdrawRequest(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0, "11");
        assertEq(w.vaultShares, vaultShares - liquidatedAmount, "22");
        assertEq(w.hasSplit, true, "33");

        (SplitWithdrawRequest memory s) = v().getSplitWithdrawRequest(w.requestId);

        assertEq(s.totalVaultShares, vaultShares, "7");
        assertEq(s.finalized, false, "8");
    }

    function test_finalizeWithdrawsManual(
        uint8 maturityIndex, uint256 depositAmount, bool useForce
    ) public {
        vm.skip(!hasWithdrawRequests());
        address account = makeAddr("account");

        uint256 vaultShares;
        uint256 positionValue;
        uint256 maturity;
        {
            maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
            maturity = maturities[maturityIndex];
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
        // Use max uint on variable lending to clear the position
        lendAmount = maturityIndex == 0 ? type(uint256).max : lendAmount;

        if (useForce) {
            _forceWithdraw(account);
        } else {
            vm.prank(account);
            v().initiateWithdraw();
        }
        WithdrawRequest memory w = v().getWithdrawRequest(account);

        {
            finalizeWithdrawRequest(account);

            vm.prank(account);
            v().finalizeWithdrawsManual(account);

            w = v().getWithdrawRequest(account);
        }

        if (w.requestId != 0) {
            SplitWithdrawRequest memory s = v().getSplitWithdrawRequest(w.requestId);
            assertTrue(w.vaultShares != 0, "5");
            assertTrue(w.hasSplit, "6");
            assertEq(w.vaultShares, s.totalVaultShares);
            assertTrue(s.finalized, "7");
            assertGe(s.totalWithdraw, positionValue, "8");
        }

        vm.startPrank(account);

        uint256 maxDiff;
        if (maturityIndex == 0) {
            maxDiff = maxRelExitValuation_WithdrawRequest_Variable;
        } else {
            maxDiff = maxRelExitValuation_WithdrawRequest_Fixed;
        }
        // exit vault and check that account received expected amount
        assertApproxEqRel(
            Deployments.NOTIONAL.exitVault(
                account, address(vault), account,
                vaultShares,
                lendAmount, 0,
                getRedeemParamsWithdrawRequest(vaultShares, maturity)
            ),
            depositAmount,
            maxDiff,
            "9"
        );

        w = v().getWithdrawRequest(account);
        _assertWithdrawRequestIsEmpty(w);
    }

    /** Helper Methods **/
    function _changeCollateralRatio() internal override {
        address token = v().STAKING_TOKEN();
        _changeTokenPrice(defaultLiquidationDiscount, token);
    }

    function _changeTokenPrice(int256 discount, address token) internal {
        (AggregatorV2V3Interface oracle, /* */) = Deployments.TRADING_MODULE.priceOracles(token);
        MockOracle mock = new MockOracle(oracle.decimals());
        mock.setAnswer(oracle.latestAnswer() * discount / 1000);

        setPriceOracle(token, address(mock));
    }

    function _liquidateAccount(address account) internal returns (address liquidator) {
        (/* */, int256[3] memory maxDeposit, /* */) = Deployments.NOTIONAL.getVaultAccountHealthFactors(
            account, address(vault)
        );
        liquidator = makeAddr("liquidator");

        uint256 maxDepositExternal = uint256(maxDeposit[0]) * precision / 1e8;
        dealTokensAndApproveNotional(maxDepositExternal * 2, liquidator);
        uint256 msgValue = address(primaryBorrowToken) == Constants.ETH_ADDRESS ? maxDepositExternal  : 0;
        vm.prank(liquidator);
        v().deleverageAccount{value: msgValue}(account, address(v()), liquidator, 0, maxDeposit[0]);
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