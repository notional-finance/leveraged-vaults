// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PendlePTOracle} from "@contracts/oracles/PendlePTOracle.sol";
import "./BaseStakingHarness.sol";
import {UniV3Adapter} from "@contracts/trading/adapters/UniV3Adapter.sol";
import "@contracts/vaults/staking/PendlePTEtherFiVault.sol";
import "@contracts/vaults/staking/BaseStakingVault.sol";

abstract contract PendleStakingHarness is BaseStakingHarness {
    address public marketAddress;
    address public ptAddress;
    uint32 twapDuration;
    bool useSyOracleRate;
    address public ptOracle;
    address public baseToUSDOracle;
    address tokenInSy;
    address public tokenOutSy;
    address public borrowToken;
    address redemptionToken;

    function deployImplementation() internal virtual returns (address);

    function deployVaultImplementation() public override returns (
        address impl, bytes memory _metadata
    ) {
        impl = deployImplementation();

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

    function withdrawToken(address vault) public view override virtual returns (address) {
        // During Pendle withdraws, the TOKEN_OUT_SY is what is being held by the vault.
        return PendlePrincipalToken(payable(vault)).TOKEN_OUT_SY();
    }
}
