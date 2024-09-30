// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseSingleSidedLPVault.sol";

abstract contract SingleSidedLPHarness is StrategyVaultHarness {

    function getMetadata() virtual public view returns (SingleSidedLPMetadata memory _m) {
        return abi.decode(metadata, (SingleSidedLPMetadata));
    }

    function setMetadata(SingleSidedLPMetadata memory _m) virtual public returns (bytes memory) {
        metadata = abi.encode(_m);
        return metadata;
    }

    function getInitializeData() public view override returns (bytes memory initData) {
        SingleSidedLPMetadata memory _m = getMetadata();

        return abi.encodeWithSelector(
            ISingleSidedLPStrategyVault.initialize.selector, InitParams({
                name: getVaultName(),
                borrowCurrencyId: _m.primaryBorrowCurrency,
                settings: _m.settings
            })
        );
    }

    function getTestVaultConfig() public view override returns (VaultConfigParams memory p) {
        SingleSidedLPMetadata memory _m = getMetadata();

        p.flags = ENABLED | ONLY_VAULT_DELEVERAGE | ALLOW_ROLL_POSITION;
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

    function hasRewardReinvestmentRole() public view virtual override returns (bool) {
        return true;
    }
}
