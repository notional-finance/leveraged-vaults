// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BaseStakingHarness.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import "@contracts/vaults/staking/PendlePTEtherFiVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

abstract contract PendleStakingHarness is BaseStakingHarness {
    address marketAddress;
    address ptAddress;
    uint32 twapDuration;
    bool useSyOracleRate;

    constructor() {
        UniV3Adapter.UniV3SingleData memory u;
        u.fee = 500; // 0.05 %
        bytes memory exchangeData = abi.encode(u);
        uint8 primaryDexId = uint8(DexId.UNISWAP_V3);

        setMetadata(StakingMetadata({
            primaryBorrowCurrency: 1,
            primaryDexId: primaryDexId,
            exchangeData: exchangeData
        }));
    }

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        impl = address(new PendlePTEtherFiVault(
            marketAddress, ptAddress, twapDuration, useSyOracleRate
        ));
        _metadata = metadata;
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
    }
}
