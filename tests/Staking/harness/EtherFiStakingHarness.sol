// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseStakingHarness.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import "@contracts/vaults/staking/EtherFiVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

contract EtherFiStakingHarness is BaseStakingHarness {

    constructor() {
        UniV3Adapter.UniV3SingleData memory u;
        u.fee = 500; // 0.05 %
        bytes memory exchangeData = abi.encode(u);
        uint8 primaryDexId = uint8(DexId.UNISWAP_V3);

        setMetadata(StakingMetadata({
            primaryBorrowCurrency: 1,
            primaryDexId: primaryDexId,
            exchangeData: exchangeData,
            hasWithdrawRequests: true
        }));
    }

    function getVaultName() public override pure returns (string memory) {
        return 'Staking:weETH:[ETH]';
    }

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        impl = address(new EtherFiVault(Constants.ETH_ADDRESS));
        _metadata = metadata;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](1);
        oracle = new address[](1);
        token[0] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        oracle[0] = 0xE47F6c47DE1F1D93d8da32309D4dB90acDadeEaE;
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
