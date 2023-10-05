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
    uint16 primaryBorrowCurrency;
    uint16 primaryDexId;
    bytes exchangeData;

    function setUp() public override {
        primaryBorrowCurrency = ETH;
        primaryDexId = uint16(DexId.CURVE_V2);

        CurveV2Adapter.CurveV2SingleData memory c;
        // wsteth/ETH pool
        c.pool = 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80;
        exchangeData = abi.encode(c);
        maxDeposit = 1e18;
        minDeposit = 0.001e18;
        maxRelEntryValuation = 15 * BASIS_POINT;
        maxRelExitValuation = 30 * BASIS_POINT;

        super.setUp();
    }

    function deployVault() internal override returns (IStrategyVault) {
        IStrategyVault impl = new CrossCurrencyVault(NOTIONAL, TRADING_MODULE, WRAPPED_FCASH_FACTORY, WETH);
        bytes memory callData = abi.encodeWithSelector(
            CrossCurrencyVault.initialize.selector, "Vault", ETH, WSTETH
        );
        lendCurrencyId = WSTETH;

        nUpgradeableBeacon beacon = new nUpgradeableBeacon(address(impl));
        nBeaconProxy proxy = new nBeaconProxy(address(beacon), callData);

        setTokenPermissions(
            address(proxy),
            address(0),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint32(primaryDexId)),
                tradeTypeFlags: uint32(1 << uint32(TradeType.EXACT_IN_SINGLE))
            })
        );

        setTokenPermissions(
            address(proxy),
            address(CrossCurrencyVault(payable(address(proxy))).LEND_UNDERLYING_TOKEN()),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint32(primaryDexId)),
                tradeTypeFlags: uint32(1 << uint32(TradeType.EXACT_IN_SINGLE))
            })
        );

        return IStrategyVault(address(proxy));
    }

    function getVaultConfig() internal view override returns (VaultConfigParams memory p) {
        p.flags = ENABLED | ALLOW_REENTRANCY | ENABLE_FCASH_DISCOUNT | VAULT_MUST_SETTLE;
        p.borrowCurrencyId = primaryBorrowCurrency;
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
    ) internal view override returns (bytes memory) {
        CrossCurrencyVault.DepositParams memory d;
        d.minPurchaseAmount = 0;
        d.minVaultShares = 0;
        d.dexId = primaryDexId;
        d.exchangeData = exchangeData;

        return abi.encode(d);
    }

    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        CrossCurrencyVault.RedeemParams memory d;
        d.minPurchaseAmount = 0;
        d.dexId = primaryDexId;
        d.exchangeData = exchangeData;

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

    function hook_beforeEnterVault(
        address /* account */,
        uint256 maturity,
        uint256 /* depositAmount */
    ) internal override {
        if (maturity != Constants.PRIME_CASH_VAULT_MATURITY) {
            WRAPPED_FCASH_FACTORY.deployWrapper(lendCurrencyId, uint40(maturity));
        }
    }

    function getPrimaryVaultToken(uint256 maturity) internal override returns (address) {
        if (maturity == Constants.PRIME_CASH_VAULT_MATURITY) {
            // NOTE: donations do not work with pCash
            return address(0);
        } else {
            return address(WRAPPED_FCASH_FACTORY.deployWrapper(lendCurrencyId, uint40(maturity)));
        }
    }

    function test_RevertIf_LendSlippageFails() public {
        address account = makeAddr("account");
        CrossCurrencyVault.DepositParams memory d;
        d.minPurchaseAmount = 0;
        d.minVaultShares = 100e8;
        d.dexId = primaryDexId;
        d.exchangeData = exchangeData;

        bytes memory params = abi.encode(d);
        hook_beforeEnterVault(account, maturities[1], 0.01e18);

        vm.expectRevert("Slippage: Vault Shares");
        enterVaultBypass(account, 0.01e18, maturities[1], params);
    }

    function test_RevertIf_BorrowSlippageFails() public {
        address account = makeAddr("account");
        CrossCurrencyVault.DepositParams memory d;
        d.minPurchaseAmount = 0;
        d.minVaultShares = 0;
        d.dexId = primaryDexId;
        d.exchangeData = exchangeData;

        bytes memory params = abi.encode(d);
        hook_beforeEnterVault(account, maturities[1], 0.01e18);
        uint256 vaultShares = enterVaultBypass(account, 0.01e18, maturities[1], params);

        CrossCurrencyVault.RedeemParams memory r;
        r.minPurchaseAmount = 100e18;
        r.dexId = primaryDexId;
        r.exchangeData = exchangeData;

        vm.expectRevert(TradeFailed.selector);
        exitVaultBypass(account, vaultShares, maturities[1], abi.encode(r));
    }

    function test_ShortCircuitOnZeroDeposit() public {
        address account = makeAddr("account");
        vm.expectCall(address(NOTIONAL), "", 0);
        uint256 vaultShares = enterVaultBypass(account, 0, maturities[1], "");
        assertEq(vaultShares, 0);
    }

    function test_ShortCircuitOnZeroRedeem() public {
        address account = makeAddr("account");
        vm.expectCall(address(NOTIONAL), "", 0);
        uint256 amount = exitVaultBypass(account, 0, maturities[1], "");
        assertEq(amount, 0);
    }
}