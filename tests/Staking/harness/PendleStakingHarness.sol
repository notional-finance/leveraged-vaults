// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PendlePTOracle} from "@contracts/oracles/PendlePTOracle.sol";
import "./BaseStakingHarness.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import "@contracts/vaults/staking/PendlePTEtherFiVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

abstract contract PendleStakingHarness is BaseStakingHarness {
    address marketAddress;
    address ptAddress;
    uint32 twapDuration;
    bool useSyOracleRate;
    address ptOracle;
    address baseToUSDOracle;

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
        impl = address(new PendlePTEtherFiVault(marketAddress, ptAddress));

        ptOracle = address(new PendlePTOracle(
            marketAddress,
            AggregatorV2V3Interface(baseToUSDOracle),
            false,
            useSyOracleRate,
            twapDuration,
            "Pendle Oracle",
            Deployments.SEQUENCER_UPTIME_ORACLE
        ));
        _metadata = metadata;
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
    }
}
