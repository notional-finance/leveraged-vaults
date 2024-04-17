// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseStakingHarness.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import "@contracts/vaults/staking/EthenaVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

contract EthenaStakingHarness is BaseStakingHarness {

    constructor() {
        setMetadata(StakingMetadata({
            primaryBorrowCurrency: 11, // simulated USDe token
            primaryDexId: 0,
            exchangeData: ""
        }));
    }

    function getVaultName() public override pure returns (string memory) {
        return 'Staking:sUSDe:[USDe]';
    }

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        // TODO: need to list USDe as a borrow token here...

        impl = address(new EthenaVault());
        _metadata = metadata;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDe
        token[0] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        oracle[0] = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;

        // sUSDe
        token[0] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        oracle[0] = 0xb99D174ED06c83588Af997c8859F93E83dD4733f;
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](0);
        permissions = new ITradingModule.TokenPermissions[](0);
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
    }
}