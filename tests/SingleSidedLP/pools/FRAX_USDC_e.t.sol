// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseCurve2Token.sol";

abstract contract FRAX_USDC_e is BaseCurve2Token {
    function initVariables() override internal {
        rewardPool = IERC20(0x93729702Bf9E1687Ae2124e191B8fFbcC0C8A0B0);
        poolToken = IERC20(0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5);
        lpToken = 0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5;
        settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100
        });
    }

    function setUp() public override virtual {
        initVariables();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.001e18;
        maxDeposit = 1e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_FRAX is FRAX_USDC_e {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Convex:[FRAX]/USDC.e';
    }

    function setUp() public override { primaryBorrowCurrency = FRAX; super.setUp(); }
}
