// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../Staking/harness/index.sol";

contract Harness_Staking_PendlePT_Generic is PendleStakingHarness {

    function getVaultName() public pure override returns (string memory) {
        return 'Pendle:PT weETH 27JUN2024:[ETH]';
    }

    function getRequiredOracles() public override view returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // Custom PT Oracle
        token[0] = ptAddress;
        oracle[0] = ptOracle;

        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);
        // weETH
        token[0] = ;
        permissions[0] = ITradingModule.TokenPermissions(
            // UniswapV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 5 }
        );
    }

    constructor() {
        marketAddress = 0x5e03c94fc5fb2e21882000a96df0b63d2c4312e2;
        ptAddress = 0x8ea5040d423410f1fdc363379af88e1db5ea1c34;
        twapDuration = 15 minutes; // recommended 15 - 30 min
        useSyOracleRate = true; // returns the weETH price
        // TODO: add ezeth
        // baseToUSDOracle = ;
    }

}
