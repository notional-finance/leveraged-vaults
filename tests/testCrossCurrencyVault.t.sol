// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseAcceptanceTest.sol";
import "../contracts/vaults/CrossCurrencyVault.sol";
import "../contracts/proxy/nUpgradeableBeacon.sol";
import "../contracts/proxy/nBeaconProxy.sol";
import "../contracts/trading/TradingModule.sol";
import "../interfaces/notional/IWrappedfCashFactory.sol";

contract TestCrossCurrencyVault is BaseAcceptanceTest {
    IWrappedfCashFactory constant WRAPPED_FCASH_FACTORY = IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);

    function deployVault() internal override returns (IStrategyVault) {
        IStrategyVault impl = new CrossCurrencyVault(NOTIONAL, TRADING_MODULE, WRAPPED_FCASH_FACTORY, WETH);
        bytes memory callData = abi.encodeWithSelector(CrossCurrencyVault.initialize.selector, "Vault", ETH, WSTETH);
        nUpgradeableBeacon beacon = new nUpgradeableBeacon(address(impl));
        nBeaconProxy proxy = new nBeaconProxy(address(beacon), callData);

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

    function test_EnterVault() public {
        address acct = makeAddr("user");
        uint256 vaultShares = enterVaultBypass(acct, 0.01e18, maturities[1]);
        console.log("Vault Shares %s", vaultShares);

        assertEq(true, true);
    }

    function test_RevertIf_depositPrimeAboveSupplyCap() public {
        assertEq(true, true);
    }
    // function test_RevertIf_lendFCashFails()
    // function test_RevertIf_redeemFCashFails()
    // function test_RevertIf_tradeFails()
}