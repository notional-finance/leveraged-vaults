// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console2 as console} from "forge-std/console2.sol";
import "@deployments/Deployments.sol";
import "@contracts/proxy/nUpgradeableBeacon.sol";
import "@contracts/proxy/nBeaconProxy.sol";
import "@contracts/trading/TradingModule.sol";
import "@interfaces/notional/IWrappedfCashFactory.sol";
import {EtherFiVault, RedeemParams, IWithdrawRequestNFT, BaseStakingVault} from "@contracts/vaults/staking/EtherFiVault.sol";
import {IStrategyVault} from "@interfaces/notional/IStrategyVault.sol";
import {WithdrawRequest, SplitWithdrawRequest} from "@interfaces/notional/IWithdrawRequest.sol";
import {ITradingModule, DexId, TradeFailed} from "@interfaces/trading/ITradingModule.sol";
import {VaultConfigParams, VaultAccount} from "@contracts/global/Types.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import {BaseAcceptanceTest} from "../BaseAcceptanceTest.sol";
import {DeployProxyVault} from "../../scripts/deploy/DeployProxyVault.sol";
import "./harness/EtherFiStakingHarness.sol";

contract Test_EtherFiVault is BaseAcceptanceTest {
    uint16 primaryBorrowCurrency;
    uint8 primaryDexId;
    bytes exchangeData;

    address weETH;
    EtherFiVault etherFiVault;

    function setUp() public override {
        harness = new EtherFiStakingHarness();

        minDeposit = 0.01e18;
        maxDeposit = 50e18;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        UniV3Adapter.UniV3SingleData memory u;
        u.fee = 500; // 0.05 %
        exchangeData = abi.encode(u);
        primaryDexId = uint8(DexId.UNISWAP_V3);
        primaryBorrowCurrency = 1; // ETH
        isETH = true;

        super.setUp();
        etherFiVault = EtherFiVault(payable(address(vault)));
    }

    function deployTestVault() internal override returns (IStrategyVault) {
        IStrategyVault impl = new EtherFiVault(Deployments.NOTIONAL, Deployments.TRADING_MODULE);
        bytes memory callData = abi.encodeWithSelector(
            BaseStakingVault.initialize.selector, "EtherFiVault", primaryBorrowCurrency
        );

        nUpgradeableBeacon beacon = new nUpgradeableBeacon(address(impl));
        nBeaconProxy proxy = new nBeaconProxy(address(beacon), callData);

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
        RedeemParams memory d;
        d.minPurchaseAmount = 0;
        d.dexId = primaryDexId;
        d.exchangeData = exchangeData;

        return abi.encode(d);
    }

    function checkInvariants() internal override {
        assertEq(
            totalVaultSharesAllMaturities,
            // TODO: make this more generic for staking tokens
            IERC20(weETH).balanceOf(address(vault)) / 1e10,
            "Total Vault Shares"
        );
    }

    function _enterEtherFiVault(
        address account, uint256 depositAmount, uint8 maturityIndex
    ) internal returns (uint256 vaultShares) {
        maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
        uint256 maturity = maturities[maturityIndex];
        depositAmount = boundDepositAmount(depositAmount);
        vaultShares =
            enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

    }

    function _assertWithdrawRequestIsEmpty(WithdrawRequest memory w) internal {
        assertEq(w.requestId, 0, "requestId should be 0");
        assertEq(w.vaultShares, 0, "vaultShares should be 0");
        assertTrue(!w.hasSplit, "hasSplit should be false");
    }


    function _forceWithdraw(address account, bool expectRevert, bytes memory error) internal {
        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        etherFiVault.grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        if (expectRevert) {
            vm.expectRevert(error);
        }
        etherFiVault.forceWithdraw(account);
    }

    function _forceWithdraw(address account) internal {
        _forceWithdraw(account, false, "");
    }

    // ok
    function test_RevertIf_BorrowSlippageFails() public {
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        bytes memory params = getDepositParams(depositAmount, maturity);
        uint256 vaultShares = enterVault(account, depositAmount, maturity, params);

        RedeemParams memory r;
        r.minPurchaseAmount = 100e18;
        r.dexId = primaryDexId;
        r.exchangeData = exchangeData;

        vm.roll(5);
        vm.warp(block.timestamp + 3600);

        vm.expectRevert(TradeFailed.selector);
        exitVaultBypass(account, vaultShares, maturity, abi.encode(r));
    }

    // ok
    function test_ShortCircuitOnZeroDeposit() public {
        address account = makeAddr("account");
        vm.expectCall(address(Deployments.NOTIONAL), "", 0);
        uint256 vaultShares = enterVaultBypass(account, 0, maturities[1], "");
        assertEq(vaultShares, 0);
    }

    // ok
    function test_ShortCircuitOnZeroRedeem() public {
        address account = makeAddr("account");
        vm.expectCall(address(Deployments.NOTIONAL), "", 0);
        uint256 amount = exitVaultBypass(account, 0, maturities[1], "");
        assertEq(amount, 0);
    }

    // ok
    function test_InitiateWithdraw_ShouldRevertIfUserHaveLessThanNeeded() public {
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        uint256 vaultShares =
            enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

        address accountWithNoShares = makeAddr("noShareAddress");

        vm.prank(accountWithNoShares);
        vm.expectRevert();
        etherFiVault.initiateWithdraw(0);

        vm.prank(accountWithNoShares);
        vm.expectRevert();
        etherFiVault.initiateWithdraw(vaultShares);
    }

    // ok
    function test_InitiateWIthdraw_RevertIf_VaultIsInitiator() public {
        address account = makeAddr("account");

        uint256 maturity = maturities[1];
        uint256 depositAmount = 2 * minDeposit;
        uint256 vaultShares =
            enterVault(account, depositAmount, maturity, getDepositParams(depositAmount, maturity));

        // TODO: set a prank here to be more explicit....
        vm.expectRevert();
        etherFiVault.initiateWithdraw(vaultShares);
    }

    // ok
    function test_InitiateWithdraw_UserShouldBeAbleToInitiateWithdraw(uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent) public {
        vm.assume(0 < withdrawPercent && withdrawPercent <= 100);
        address account = makeAddr("account");

        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        (
            WithdrawRequest memory f,
            WithdrawRequest memory w
        ) = etherFiVault.getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(f);
        _assertWithdrawRequestIsEmpty(w);

        uint256 vaultShareToWithdraw = vaultShares * withdrawPercent / 100;
        vm.prank(account);
        etherFiVault.initiateWithdraw(vaultShareToWithdraw);

        (f, w) = etherFiVault.getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(f);
        assertTrue(w.requestId != 0);
        assertEq(w.vaultShares, vaultShareToWithdraw);
        assertEq(w.hasSplit, false);
        // TODO: assert no change to account value
    }

    function test_InitiateWithdraw_RevertIf_InitiateMultipleWithdraws(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent, uint8 secondWithdrawPercent
    ) public {
        vm.assume(0 < withdrawPercent && withdrawPercent < 100);
        address account = makeAddr("account");

        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        vm.prank(account);
        etherFiVault.initiateWithdraw(vaultShares * withdrawPercent / 100);

        secondWithdrawPercent = uint8(bound(secondWithdrawPercent, 1, 100 - withdrawPercent));
        vm.prank(account);
        vm.expectRevert("Existing Request");
        etherFiVault.initiateWithdraw(vaultShares * secondWithdrawPercent / 100);
    }

    // ok
    function test_InitiateWithdraw_ShouldBeAbleToForceWithdrawTheRestByAdmin(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        vm.assume(0 < withdrawPercent && withdrawPercent < 100);
        address account = makeAddr("account");

        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        uint256 vaultShareToWithdraw = vaultShares * withdrawPercent / 100;

        vm.prank(account);
        etherFiVault.initiateWithdraw(vaultShareToWithdraw);
        (
            WithdrawRequest memory f,
            WithdrawRequest memory w
        ) = etherFiVault.getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(f);
        assertTrue(w.requestId != 0, "4");
        assertEq(w.vaultShares, vaultShareToWithdraw, "5");
        assertEq(w.hasSplit, false, "6");

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        etherFiVault.grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        etherFiVault.forceWithdraw(account);

        (f, w) = etherFiVault.getWithdrawRequests(account);
        assertTrue(f.requestId != 0, "7");
        assertEq(f.vaultShares, vaultShares - vaultShareToWithdraw, "8");
        assertEq(f.hasSplit, false, "9");
        assertTrue(w.requestId != 0, "10");
        assertEq(w.vaultShares, vaultShareToWithdraw, "11");
        assertEq(w.hasSplit, false, "12");
    }

    // TODO: verify this one in the code....
    function test_InitiateWithdraw_ShouldNotBeAbleInitiateWithdrawAfterForceWithdraw(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        vm.assume(0 < withdrawPercent && withdrawPercent < 100);
        address account = makeAddr("account");

        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        etherFiVault.grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        etherFiVault.forceWithdraw(account);


        vm.prank(account);
        vm.expectRevert("Existing Request");
        etherFiVault.initiateWithdraw(vaultShares * withdrawPercent / 100);
    }

    // ok
    function test_ForceWithdraw_AdminShouldBeAbleToInitiateForceWithdrawForAccount(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        address account = makeAddr("account");

        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        address admin = makeAddr("admin");
        vm.prank(Deployments.NOTIONAL.owner());
        etherFiVault.grantRole(keccak256("EMERGENCY_EXIT_ROLE"), admin);
        vm.prank(admin);
        etherFiVault.forceWithdraw(account);
        (
            WithdrawRequest memory f,
            WithdrawRequest memory w
        ) = etherFiVault.getWithdrawRequests(account);
        _assertWithdrawRequestIsEmpty(w);
        assertTrue(f.requestId != 0, "4");
        assertEq(f.vaultShares, vaultShares, "5");
        assertEq(f.hasSplit, false, "6");
    }

    // ok
    function test_ForceWithdraw_AdminShouldNotBeAbleToInitiateForceWithdrawSecondTime(
        uint8 maturityIndex, uint256 depositAmount
    ) public {
        address account = makeAddr("account");
        _enterEtherFiVault(account, depositAmount, maturityIndex);

        _forceWithdraw(account);
        _forceWithdraw({ account: account, expectRevert: true, error: "Existing Request" });
    }

    function _liquidateAccount(address account) internal returns (address liquidator) {
        // set vault settings so account can be liquidated
        config.minCollateralRatioBPS = 10000;
        config.maxDeleverageCollateralRatioBPS = config.minCollateralRatioBPS + 1;
        config.maxRequiredAccountCollateralRatioBPS = config.maxDeleverageCollateralRatioBPS + 100;
        vm.prank(Deployments.NOTIONAL.owner());
        Deployments.NOTIONAL.updateVault(address(vault), config, getMaxPrimaryBorrow());

        liquidator = makeAddr("liquidator");
        uint256 value = 100 ether;
        deal(liquidator, value);
        vm.prank(liquidator);
        etherFiVault.deleverageAccount{value: value }(account, address(etherFiVault), liquidator, 0, int256(value / 1e10));
    }

    function test_DeleverageAccount_WhenThereIsNoPreviousWithdrawRequest(uint8 maturityIndex, uint256 depositAmount) public {
        address account = makeAddr("account");
        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(etherFiVault));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(etherFiVault));


        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = etherFiVault.getWithdrawRequests(account);
        // should not have initiated withdrew request
        _assertWithdrawRequestIsEmpty(w);
        _assertWithdrawRequestIsEmpty(f);
    }

    function test_DeleverageAccount_WhenThereIsExistingWithdrawRequestButStillEnoughLiquidShares(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        withdrawPercent = uint8(bound(withdrawPercent, 1, 5));
        address account = makeAddr("account");
        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        uint256 vaultSharesForWithdraw = vaultShares * withdrawPercent / 100;
        vm.prank(account);
        etherFiVault.initiateWithdraw(vaultSharesForWithdraw);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(etherFiVault));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(etherFiVault));


        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = etherFiVault.getWithdrawRequests(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0, "11");
        assertEq(w.vaultShares, vaultSharesForWithdraw, "22");
        assertEq(w.hasSplit, false, "33");
        _assertWithdrawRequestIsEmpty(f);
    }

    function test_DeleverageAccount_WhenThereIsExistingWithdrawRequestThatNeedsSplitting(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        withdrawPercent = uint8(bound(withdrawPercent, 95, 100));
        address account = makeAddr("account");
        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        uint256 vaultSharesForWithdraw = vaultShares * withdrawPercent / 100;
        vm.prank(account);
        etherFiVault.initiateWithdraw(vaultSharesForWithdraw);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(etherFiVault));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(etherFiVault));


        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        uint256 splittedVaultShares = liquidatedAmount - (vaultShares - vaultSharesForWithdraw);
        (WithdrawRequest memory f, WithdrawRequest memory w) = etherFiVault.getWithdrawRequests(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0, "11");
        assertEq(w.vaultShares, vaultSharesForWithdraw - splittedVaultShares, "22");
        assertEq(w.hasSplit, true, "33");
        _assertWithdrawRequestIsEmpty(f);

        (SplitWithdrawRequest memory s) = etherFiVault.getSplitWithdrawRequest(w.requestId);

        assertEq(s.totalVaultShares, vaultSharesForWithdraw, "7");
        assertEq(s.finalized, false, "8");
    }

    function test_DeleverageAccount_WhenThereIsExistingWithdrawRequestThatNeedsSplittingWithForceWithdraw(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        withdrawPercent = uint8(bound(withdrawPercent, 95, 98));
        address account = makeAddr("account");
        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        uint256 vaultSharesForWithdraw = vaultShares * withdrawPercent / 100;
        vm.prank(account);
        etherFiVault.initiateWithdraw(vaultSharesForWithdraw);

        _forceWithdraw(account);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(etherFiVault));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(etherFiVault));


        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = etherFiVault.getWithdrawRequests(account);
        // withdraw request should be unchanged after liquidation
        assertTrue(w.requestId != 0, "1");
        assertEq(w.vaultShares, vaultSharesForWithdraw - liquidatedAmount, "2");
        assertEq(w.hasSplit, true, "3");
        assertTrue(f.requestId != 0, "4");
        assertEq(f.vaultShares, vaultShares - vaultSharesForWithdraw, "5");
        assertEq(f.hasSplit, false, "6");

        (WithdrawRequest memory lf, WithdrawRequest memory lw) = etherFiVault.getWithdrawRequests(liquidator);

        assertTrue(lw.requestId != 0, "11");
        assertEq(lw.vaultShares, liquidatedAmount, "22");
        assertEq(lw.hasSplit, true, "33");
        _assertWithdrawRequestIsEmpty(lf);

        (SplitWithdrawRequest memory s) = etherFiVault.getSplitWithdrawRequest(w.requestId);
        assertEq(s.totalVaultShares, vaultSharesForWithdraw, "7");
        assertEq(s.finalized, false, "8");
    }

    function test_DeleverageAccount_WhenForceWithdrawNeedsSplitting(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        withdrawPercent = uint8(bound(withdrawPercent, 0, 5));
        address account = makeAddr("account");
        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, maturityIndex);

        uint256 vaultSharesForWithdraw = vaultShares * withdrawPercent / 100;
        if (vaultSharesForWithdraw != 0) {
            vm.prank(account);
            etherFiVault.initiateWithdraw(vaultSharesForWithdraw);
        }

        _forceWithdraw(account);

        address liquidator = _liquidateAccount(account);

        (VaultAccount memory vaultAccount) = Deployments.NOTIONAL.getVaultAccount(account, address(etherFiVault));
        (VaultAccount memory liquidatorAccount) = Deployments.NOTIONAL.getVaultAccount(liquidator, address(etherFiVault));


        uint256 liquidatedAmount = vaultShares - vaultAccount.vaultShares;
        assertGt(liquidatedAmount, 0, "Liquidated amount should be larger than 0");
        assertEq(liquidatorAccount.vaultShares, liquidatedAmount, "Liquidator account should receive liquidated amount");

        (WithdrawRequest memory f, WithdrawRequest memory w) = etherFiVault.getWithdrawRequests(account);
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

        (WithdrawRequest memory lf, WithdrawRequest memory lw) = etherFiVault.getWithdrawRequests(liquidator);
        assertTrue(lw.requestId != 0, "11");
        assertEq(lw.vaultShares, liquidatedAmount, "22");
        assertEq(lw.hasSplit, true, "33");
        _assertWithdrawRequestIsEmpty(lf);

        (SplitWithdrawRequest memory s) = etherFiVault.getSplitWithdrawRequest(f.requestId);
        assertEq(s.totalVaultShares,  vaultShares - vaultSharesForWithdraw, "7");
        assertEq(s.finalized, false, "8");
    }

    function test_convertStrategyToUnderlying(uint256 depositAmount) public {
        address account = makeAddr("account");

        uint256 vaultShares = _enterEtherFiVault(account, depositAmount, 0);

        (int256 rate, /* int256 rateDecimals */) = Deployments.TRADING_MODULE.getOraclePrice(
            address(weETH), address(primaryBorrowToken)
        );

        assertEq(
            uint256(etherFiVault.convertStrategyToUnderlying(account, vaultShares, 0)),
            vaultShares * uint256(rate) / uint256(Constants.INTERNAL_TOKEN_PRECISION)
        );
    }

    // TODO: test that you can exit with one withdraw request, a forced withdraw request and both
    function test_exitVaultWithoutSelling(
        uint8 maturityIndex, uint256 depositAmount, uint8 withdrawPercent
    ) public {
        vm.assume(0 < withdrawPercent && withdrawPercent <= 100);
        address account = makeAddr("account");

        maturityIndex = uint8(bound(maturityIndex, 0, maturities.length - 1));
        uint256 maturity = maturities[maturityIndex];
        depositAmount = boundDepositAmount(depositAmount);

        uint256 vaultShares = enterVault(
            account,
            depositAmount,
            maturity,
            getDepositParams(depositAmount, maturity)
        );

        vm.warp(block.timestamp + 3600);

        uint256 lendAmount;
        if (maturity == type(uint40).max) {
          lendAmount = type(uint256).max;
        } else {
          lendAmount = uint256(
            Deployments.NOTIONAL.getVaultAccount(account, address(vault)).accountDebtUnderlying * -1
          );
        }
        vm.prank(account);
        // should fail if withdraw is not initiated
        vm.expectRevert();
        uint256 totalToReceiver = Deployments.NOTIONAL.exitVault(account, address(vault), account, vaultShares, lendAmount, 0, "");

        vm.prank(account);
        etherFiVault.initiateWithdraw(vaultShares);
        (, WithdrawRequest memory w) = etherFiVault.getWithdrawRequests(account);

        vm.prank(account);
        // should fail if withdraw is not finalized
        vm.expectRevert();
        totalToReceiver = Deployments.NOTIONAL.exitVault(account, address(vault), account, vaultShares, lendAmount, 0, "");

        vm.warp(block.timestamp + 7 days);
        IWithdrawRequestNFT withdrawRequestNFT = etherFiVault.WithdrawRequestNFT();
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705); // etherFi: admin
        withdrawRequestNFT.finalizeRequests(w.requestId);

        vm.prank(account);
        totalToReceiver = Deployments.NOTIONAL.exitVault(account, address(vault), account, vaultShares, lendAmount, 0, "");
    }
}