// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../StrategyVaultHarness.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

struct StakingMetadata {
    uint16 primaryBorrowCurrency;
}

contract EtherFiStakingHarness is StrategyVaultHarness {

    constructor() {
        setMetadata(StakingMetadata({ primaryBorrowCurrency: 1 }));
    }

    function getVaultName() public override pure returns (string memory) {
        return 'EtherFiVault';
    }

    function getMetadata() virtual public view returns (StakingMetadata memory _m) {
        return abi.decode(metadata, (StakingMetadata));
    }

    function setMetadata(StakingMetadata memory _m) virtual internal returns (bytes memory) {
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

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {

    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);
        token[0] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        permissions[0] = ITradingModule.TokenPermissions(
            // UniswapV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 5 }
        );
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
    }
}
