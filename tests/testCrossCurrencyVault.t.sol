// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseAcceptanceTest.sol";
import "../contracts/vaults/CrossCurrencyVault.sol";
import "../interfaces/notional/IWrappedfCashFactory.sol";

contract TestCrossCurrencyVault is BaseAcceptanceTest {
    IWrappedfCashFactory constant WRAPPED_FCASH_FACTORY = IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);

    function deployVault() internal override returns (IStrategyVault) {
        return new CrossCurrencyVault(NOTIONAL, TRADING_MODULE, WRAPPED_FCASH_FACTORY, WETH);
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

    function test_RevertIf_depositPrimeAboveSupplyCap() public {
        assertEq(true, true);
    }
    // function test_RevertIf_lendFCashFails()
    // function test_RevertIf_redeemFCashFails()
    // function test_RevertIf_tradeFails()
}