// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseCurve2Token.sol";

abstract contract FRAX_USDC_e is BaseCurve2Token {
    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDC_e
        token[0] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        // Chainlink USDC/USD
        oracle[0] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

        // USDT
        token[1] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        // Chainlink USDT/USD
        oracle[1] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x971E732B5c91A59AEa8aa5B0c763E6d648362CF8);
        poolToken = IERC20(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
        lpToken = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
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
        minDeposit = 0.001e6;
        maxDeposit = 1e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_FRAX is FRAX_USDC_e {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Convex:USDC.e/[USDT]';
    }

    function setUp() public override { 
        primaryBorrowCurrency = USDT;
        super.setUp();
    }
}