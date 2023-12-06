// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseCurve2Token.sol";

abstract contract FRAX_USDC_e is BaseCurve2Token {
    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // FRAX
        token[0] = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
        // Chainlink FRAX/USD
        oracle[0] = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;

        // USDC.e
        token[1] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        // Chainlink USDC/USD
        oracle[1] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    }

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

    function setUp() public override { 
        EXISTING_DEPLOYMENT = 0xdb08f663e5D765949054785F2eD1b2aa1e9C22Cf;
        primaryBorrowCurrency = FRAX;
        super.setUp();
    }
}
