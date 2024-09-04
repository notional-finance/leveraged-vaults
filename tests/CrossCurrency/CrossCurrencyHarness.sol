// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../StrategyVaultHarness.sol";
import "@contracts/proxy/nUpgradeableBeacon.sol";
import "@contracts/proxy/nBeaconProxy.sol";
import "@deployments/Deployments.sol";
import "@contracts/vaults/notional/CrossCurrencyVault.sol";

struct CrossCurrencyMetadata {
    uint16 primaryBorrowCurrency;
    uint16 lendCurrencyId;
    address beacon;
}

abstract contract CrossCurrencyHarness is StrategyVaultHarness {

    function getMetadata() public view returns (CrossCurrencyMetadata memory _m) {
        return abi.decode(metadata, (CrossCurrencyMetadata));
    }

    function setMetadata(CrossCurrencyMetadata memory _m) public returns (bytes memory) {
        metadata = abi.encode(_m);
        return metadata;
    }

    function getInitializeData() public view override returns (bytes memory initData) {
        CrossCurrencyMetadata memory _m = getMetadata();

        return abi.encodeWithSelector(CrossCurrencyVault.initialize.selector,
            getVaultName(),
            _m.primaryBorrowCurrency,
            _m.lendCurrencyId
        );
    }

    function getTestVaultConfig() public view override returns (VaultConfigParams memory p) {
        CrossCurrencyMetadata memory _m = getMetadata();

        p.flags = ENABLED | ALLOW_REENTRANCY | ENABLE_FCASH_DISCOUNT | VAULT_MUST_SETTLE;
        p.borrowCurrencyId = _m.primaryBorrowCurrency;
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

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        CrossCurrencyMetadata memory _m = getMetadata();

        if (_m.beacon == address(0)) {
            address implementation = address(new CrossCurrencyVault(
                Deployments.NOTIONAL,
                Deployments.TRADING_MODULE,
                Deployments.WRAPPED_FCASH_FACTORY,
                Deployments.WETH
            ));
            _m.beacon = address(new nUpgradeableBeacon(implementation));
        }

        nBeaconProxy proxy = new nBeaconProxy(_m.beacon, getInitializeData());

        _metadata = setMetadata(_m);
        impl = address(proxy);
    }
}