// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PendlePTOracle} from "@contracts/oracles/PendlePTOracle.sol";
import "./BaseStakingHarness.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import "@contracts/vaults/staking/PendlePTEtherFiVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

// TODO: there are custom pendle tests
abstract contract PendleStakingHarness is BaseStakingHarness {
    address public marketAddress;
    address public ptAddress;
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
            // TODO: this us custom per pendle vault
            primaryBorrowCurrency: 1,
            primaryDexId: primaryDexId,
            exchangeData: exchangeData
        }));
    }

    // TODO: this is custom per pendle vault
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

    function withdrawToken(address vault) public view override returns (address) {
        // During Pendle withdraws, the TOKEN_OUT_SY is what is being held by the vault.
        return PendlePrincipalToken(payable(vault)).TOKEN_OUT_SY();
    }
}
