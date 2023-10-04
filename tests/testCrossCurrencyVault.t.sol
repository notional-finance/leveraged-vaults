// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseAcceptanceTest.sol";
import "../contracts/vaults/CrossCurrencyVault.sol";
import "../contracts/proxy/nUpgradeableBeacon.sol";
import "../contracts/proxy/nBeaconProxy.sol";
import "../contracts/trading/TradingModule.sol";
import "../interfaces/notional/IWrappedfCashFactory.sol";
import "../interfaces/trading/ITradingModule.sol";

contract TestCrossCurrencyVault is BaseAcceptanceTest {
    IWrappedfCashFactory constant WRAPPED_FCASH_FACTORY = IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
    uint16 lendCurrencyId;

    function deployVault() internal override returns (IStrategyVault) {
        IStrategyVault impl = new CrossCurrencyVault(NOTIONAL, TRADING_MODULE, WRAPPED_FCASH_FACTORY, WETH);
        bytes memory callData = abi.encodeWithSelector(
            CrossCurrencyVault.initialize.selector, "Vault", ETH, WSTETH
        );
        lendCurrencyId = WSTETH;

        nUpgradeableBeacon beacon = new nUpgradeableBeacon(address(impl));
        nBeaconProxy proxy = new nBeaconProxy(address(beacon), callData);

        vm.startPrank(0xE6FB62c2218fd9e3c948f0549A2959B509a293C8);
        TRADING_MODULE.setTokenPermissions(
            address(proxy),
            address(0),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint32(DexId.CURVE_V2)),
                tradeTypeFlags: uint32(1 << uint32(TradeType.EXACT_IN_SINGLE))
            })
        );

        TRADING_MODULE.setTokenPermissions(
            address(proxy),
            address(CrossCurrencyVault(payable(address(proxy))).LEND_UNDERLYING_TOKEN()),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint32(DexId.CURVE_V2)),
                tradeTypeFlags: uint32(1 << uint32(TradeType.EXACT_IN_SINGLE))
            })
        );
        vm.stopPrank();

        return IStrategyVault(address(proxy));
    }

    function getVaultConfig() internal pure override returns (VaultConfigParams memory p) {
        p.flags = ENABLED | ALLOW_REENTRANCY | ENABLE_FCASH_DISCOUNT | VAULT_MUST_SETTLE;
        p.borrowCurrencyId = ETH;
        p.minAccountBorrowSize = 0.01e8;
        p.minCollateralRatioBPS = 5000;
        p.feeRate5BPS = 5;
        p.liquidationRate = 102;
        p.reserveFeeShare = 80;
        p.maxBorrowMarketIndex = 2;
        p.maxDeleverageCollateralRatioBPS = 7000;
        p.maxRequiredAccountCollateralRatioBPS = 10000;
        p.excessCashLiquidationBonus = 100;
    }

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal pure override returns (bytes memory) {
        CrossCurrencyVault.DepositParams memory d;
        d.minPurchaseAmount = 0;
        d.minVaultShares = 0;
        d.dexId = uint16(DexId.CURVE_V2);

        CurveV2Adapter.CurveV2SingleData memory c;
        // wsteth/ETH pool
        c.pool = 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80;
        d.exchangeData = abi.encode(c);

        return abi.encode(d);
    }

    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal pure override returns (bytes memory) {
        CrossCurrencyVault.RedeemParams memory d;
        d.minPurchaseAmount = 0;
        d.dexId = uint16(DexId.CURVE_V2);

        CurveV2Adapter.CurveV2SingleData memory c;
        // wsteth/ETH pool
        c.pool = 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80;
        d.exchangeData = abi.encode(c);

        return abi.encode(d);
    }

    function checkInvariants() internal override {
        IERC20 pCash = IERC20(NOTIONAL.pCashAddress(lendCurrencyId));

        assertEq(
            totalVaultShares[maturities[0]],
            pCash.balanceOf(address(vault)),
            "Prime Cash Balance"
        );

        for (uint256 i = 1; i < maturities.length; i++) {
            IERC20 w = IERC20(
                address(WRAPPED_FCASH_FACTORY.deployWrapper(lendCurrencyId, uint40(maturities[i])))
            );
            assertEq(
                totalVaultShares[maturities[i]],
                w.balanceOf(address(vault)),
                "fCash Balance"
            );
        }
    }

    function test_EnterVault(uint256 maturityIndex) public {
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        address acct = makeAddr("user");

        if (maturity != Constants.PRIME_CASH_VAULT_MATURITY) {
            WRAPPED_FCASH_FACTORY.deployWrapper(lendCurrencyId, uint40(maturity));
        }

        uint256 depositAmount = 0.1e18;
        uint256 vaultShares = enterVaultBypass(acct, depositAmount, maturity);
        int256 valuationAfter = vault.convertStrategyToUnderlying(
            acct, vaultShares, maturity
        );

        assertRelDiff(
            uint256(valuationAfter),
            depositAmount,
            10 * BASIS_POINT,
            "Valuation and Deposit"
        );

        checkInvariants();
    }

    function test_ExitVault(uint256 maturityIndex) public {
        maturityIndex = bound(maturityIndex, 0, maturities.length - 1);
        uint256 maturity = maturities[maturityIndex];
        address acct = makeAddr("user");

        if (maturity != Constants.PRIME_CASH_VAULT_MATURITY) {
            WRAPPED_FCASH_FACTORY.deployWrapper(lendCurrencyId, uint40(maturity));
        }

        uint256 depositAmount = 0.1e18;
        uint256 vaultShares = enterVaultBypass(acct, depositAmount, maturity);

        vm.roll(5);
        vm.warp(block.timestamp + 3600);

        int256 valuationBefore = vault.convertStrategyToUnderlying(
            acct, vaultShares, maturity
        );
        uint256 underlyingToReceiver = exitVaultBypass(acct, vaultShares, maturity);

        assertRelDiff(
            uint256(valuationBefore),
            underlyingToReceiver,
            10 * BASIS_POINT,
            "Valuation and Deposit"
        );

        checkInvariants();
    }

    // function test_RevertIf_depositPrimeAboveSupplyCap()
    // function test_RevertIf_lendFCashFails()
    // function test_RevertIf_redeemFCashFails()
    // function test_RevertIf_tradeFails()
}