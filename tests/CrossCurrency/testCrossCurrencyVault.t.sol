// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseCrossCurrencyVault.sol";

contract TestCrossCurrency_ETH_WSTETH is BaseCrossCurrencyVault {
    function setUp() public override {
        primaryBorrowCurrency = ETH;
        lendCurrencyId = WSTETH;
        primaryDexId = uint16(DexId.CURVE_V2);

        CurveV2Adapter.CurveV2SingleData memory c;
        // wsteth/ETH pool
        c.pool = 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80;
        exchangeData = abi.encode(c);
        maxDeposit = 1e18;
        minDeposit = 0.001e18;
        maxRelEntryValuation = 30 * BASIS_POINT;
        maxRelExitValuation = 30 * BASIS_POINT;

        super.setUp();
    }
}

contract TestCrossCurrency_WSTETH_ETH is BaseCrossCurrencyVault {
    function setUp() public override {
        primaryBorrowCurrency = WSTETH;
        lendCurrencyId = ETH;
        primaryDexId = uint16(DexId.CURVE_V2);

        CurveV2Adapter.CurveV2SingleData memory c;
        // wsteth/ETH pool
        c.pool = 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80;
        exchangeData = abi.encode(c);
        maxDeposit = 1e18;
        minDeposit = 0.001e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 30 * BASIS_POINT;

        super.setUp();
    }
}
