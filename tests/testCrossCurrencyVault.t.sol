// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseAcceptanceTest.sol";
import "../interfaces/notional/IWrappedfCashFactory.sol";

contract TestCrossCurrencyVault is BaseAcceptanceTest {
    IWrappedfCashFactory constant WRAPPED_FCASH_FACTORY = IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);

    function deployVault() internal override return (IStrategyVault) {
        return new CrossCurrencyVault(NOTIONAL, TRADING_MODULE, WRAPPED_FCASH_FACTORY, WETH);
    }

    function getVaultConfig() internal override return (VaultConfigParams memory) {
        return VaultConfigParams({
            flags: getFlags(),
            borrowCurrencyId: ETH,
            minAccountBorrowSize: 0.01e8,
            minCollateralRatioBPS: 5000,
            feeRate5BPS: 5,
            liquidationRate: 102,
            reserveFeeShare: 80,
            maxBorrowMarketIndex: 2
            maxDeleverageCollateralRatioBPS: 7000,
            maxRequiredAccountCollateralRatioBPS: 10000,
            secondaryBorrowCurrencies: new uint16[](2),
            minAccountSecondaryBorrow: new uint16[](2),
            excessCashLiquidationBonus: 100
        })
    }

    function setUp() public {
        super.setUp();
    }

    // function test_RevertIf_depositPrimeAboveSupplyCap()
    // function test_RevertIf_lendFCashFails()
    // function test_RevertIf_redeemFCashFails()
    // function test_RevertIf_tradeFails()
}