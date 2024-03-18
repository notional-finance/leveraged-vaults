// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseAcceptanceTest.sol";
import "@contracts/vaults/notional/CrossCurrencyVault.sol";
import "@contracts/proxy/nUpgradeableBeacon.sol";
import "@contracts/proxy/nBeaconProxy.sol";
import "@contracts/trading/TradingModule.sol";
import "@interfaces/notional/IWrappedfCashFactory.sol";
import "@interfaces/trading/ITradingModule.sol";

abstract contract BaseCrossCurrencyVault is BaseAcceptanceTest {
    IWrappedfCashFactory constant WRAPPED_FCASH_FACTORY = IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
    uint16 lendCurrencyId;
    uint16 primaryBorrowCurrency;
    uint16 primaryDexId;
    bytes exchangeData;

    function deployTestVault() internal override returns (IStrategyVault) {
        IStrategyVault impl = new CrossCurrencyVault(
            Deployments.NOTIONAL, Deployments.TRADING_MODULE, WRAPPED_FCASH_FACTORY, Deployments.WETH
        );
        bytes memory callData = abi.encodeWithSelector(
            CrossCurrencyVault.initialize.selector, "Vault", primaryBorrowCurrency, lendCurrencyId
        );

        nUpgradeableBeacon beacon = new nUpgradeableBeacon(address(impl));
        nBeaconProxy proxy = new nBeaconProxy(address(beacon), callData);
        (/* */, Token memory underlyingToken) = Deployments.NOTIONAL.getCurrency(primaryBorrowCurrency);

        // Start with the first index
        for (uint256 i = 1; i < maturities.length; i++) {
            WRAPPED_FCASH_FACTORY.deployWrapper(lendCurrencyId, uint40(maturities[i]));
        }

        setTokenPermissions(
            address(proxy),
            underlyingToken.tokenAddress,
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
        IERC20 pCash = IERC20(Deployments.NOTIONAL.pCashAddress(lendCurrencyId));

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

        expectRevert_enterVaultBypass(account, 0.01e18, maturities[1], params, "Slippage: Vault Shares");
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
        vm.expectCall(address(Deployments.NOTIONAL), "", 0);
        uint256 vaultShares = enterVaultBypass(account, 0, maturities[1], "");
        assertEq(vaultShares, 0);
    }

    function test_ShortCircuitOnZeroRedeem() public {
        address account = makeAddr("account");
        vm.expectCall(address(Deployments.NOTIONAL), "", 0);
        uint256 amount = exitVaultBypass(account, 0, maturities[1], "");
        assertEq(amount, 0);
    }
}