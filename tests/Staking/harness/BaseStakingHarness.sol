// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../StrategyVaultHarness.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

struct StakingMetadata {
    uint16 primaryBorrowCurrency;
    uint8 primaryDexId;
    bytes exchangeData;
    bool hasWithdrawRequests;
}

abstract contract BaseStakingHarness is StrategyVaultHarness {

    function getMetadata() virtual public view returns (StakingMetadata memory _m) {
        return abi.decode(metadata, (StakingMetadata));
    }

    function setMetadata(StakingMetadata memory _m) virtual public returns (bytes memory) {
        metadata = abi.encode(_m);
        return metadata;
    }

    function getInitializeData() public view override returns (bytes memory initData) {
        StakingMetadata memory _m = getMetadata();

        return abi.encodeWithSelector(
            BaseStakingVault.initialize.selector,
            getVaultName(), _m.primaryBorrowCurrency
        );
    }

    function getTestVaultConfig() public view override returns (VaultConfigParams memory p) {
        StakingMetadata memory _m = getMetadata();

        p.flags = ENABLED | ONLY_VAULT_DELEVERAGE | ALLOW_ROLL_POSITION;
        p.borrowCurrencyId = _m.primaryBorrowCurrency;
        p.minAccountBorrowSize = 0.01e8;
        p.minCollateralRatioBPS = 500;
        p.feeRate5BPS = 5;
        p.liquidationRate = 102;
        p.reserveFeeShare = 80;
        p.maxBorrowMarketIndex = 2;
        p.maxDeleverageCollateralRatioBPS = 7000;
        p.maxRequiredAccountCollateralRatioBPS = 10000;
        p.excessCashLiquidationBonus = 100;
    }

    function withdrawToken(address vault) public view virtual returns (address) {
        return BaseStakingVault(payable(vault)).STAKING_TOKEN();
    }
}
