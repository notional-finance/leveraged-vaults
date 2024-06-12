// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseStakingHarness.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import "@contracts/vaults/staking/EthenaVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

contract EthenaStakingHarness is BaseStakingHarness {

    constructor() {
        setMetadata(StakingMetadata({
            primaryBorrowCurrency: 8,
            primaryDexId: 2, // UniV3
            exchangeData: abi.encode(UniV3Adapter.UniV3SingleData({
                fee: 100
            })),
            hasWithdrawRequests: true
        }));
    }

    function getVaultName() public override pure returns (string memory) {
        return 'Staking:sUSDe:[USDe]';
    }

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        impl = address(new EthenaVault(0xdAC17F958D2ee523a2206206994597C13D831ec7));
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

        // USDT
        token[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        oracle[2] = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](4);
        permissions = new ITradingModule.TokenPermissions[](4);

        // USDT
        token[0] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        permissions[0] = ITradingModule.TokenPermissions(
            // UniV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 1 }
        );

        // sUSDe
        token[1] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        permissions[1] = ITradingModule.TokenPermissions(
            // CurveV2, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 128, tradeTypeFlags: 1 }
        );

        // DAI: required to exit sDAI pool
        token[2] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        permissions[2] = ITradingModule.TokenPermissions(
            // UniV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 1 }
        );

        // USDe
        token[3] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        permissions[3] = ITradingModule.TokenPermissions(
            // UniV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 1 }
        );
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
    }

    function withdrawToken(address vault) public view override returns (address) {
        // Due to the design of Ethena's withdraw mechanism, USDe is already held
        // in escrow for the cooldown.
        return BaseStakingVault(payable(vault)).REDEMPTION_TOKEN();
    }
}