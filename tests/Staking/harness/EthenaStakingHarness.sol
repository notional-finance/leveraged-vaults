// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseStakingHarness.sol";
import {CurveV2Adapter} from "@contracts/trading/adapters/CurveV2Adapter.sol";
import "@contracts/vaults/staking/EthenaVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

contract EthenaStakingHarness is BaseStakingHarness {

    constructor() {
        setMetadata(StakingMetadata({
            primaryBorrowCurrency: 3,
            primaryDexId: 8,
            // USDC-USDe Curve Pool
            exchangeData: abi.encode(CurveV2Adapter.CurveV2SingleData(
                0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72
            ))
        }));
    }

    function getVaultName() public override pure returns (string memory) {
        return 'Staking:sUSDe:[USDe]';
    }

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        impl = address(new EthenaVault());
        _metadata = metadata;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](3);
        oracle = new address[](3);

        // USDe
        token[0] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        oracle[0] = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;

        // sUSDe
        token[1] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        oracle[1] = 0xb99D174ED06c83588Af997c8859F93E83dD4733f;

        // USDC
        token[2] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[2] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
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