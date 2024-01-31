// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../BaseComposablePool.sol";

abstract contract USDC_DAI_USDT_USDC_e is BaseComposablePool {
    function getRequiredOracles() internal override view virtual returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](4);
        oracle = new address[](4);
        // USDC
        token[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        // Chainlink USDC/USD
        oracle[0] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;

        // DAI
        token[1] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        // Chainlink DAI/USD
        oracle[1] = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;

        // USDT
        token[2] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        // Chainlink USDT/USD
        oracle[2] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;

        // USDC.e
        token[3] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        // Chainlink USDC/USD
        oracle[3] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    }

    function initVariables() override internal {
        rewardPool = IERC20(0x416C7Ad55080aB8e294beAd9B8857266E3B3F28E);
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
        maxRelEntryValuation = 10 * BASIS_POINT;
        maxRelExitValuation = 10 * BASIS_POINT;
        super.setUp();
    }
}

contract Test_USDC is USDC_DAI_USDT_USDC_e {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:[USDC]/DAI/USDT/USDC.e';
    }

    function getDeploymentConfig() internal view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1100;
        params.maxRequiredAccountCollateralRatioBPS = 10_000;
        params.maxDeleverageCollateralRatioBPS = 1700;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 5_000e8;
        maxPrimaryBorrow = 300_000e8;
    }

    function setUp() public override { 
        EXISTING_DEPLOYMENT = 0x8Ae7A8789A81A43566d0ee70264252c0DB826940;
        primaryBorrowCurrency = USDC;
        super.setUp();

        minDeposit = 0.01e6;
        maxDeposit = 100_000e6;
    }
}

contract Test_DAI is USDC_DAI_USDT_USDC_e {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:USDC/[DAI]/USDT/USDC.e';
    }

    function setUp() public override { 
        primaryBorrowCurrency = DAI;
        super.setUp();

        minDeposit = 0.01e18;
        maxDeposit = 100_000e18;
    }
}

contract Test_USDT is USDC_DAI_USDT_USDC_e {
    function getVaultName() internal pure override returns (string memory) {
        return 'SingleSidedLP:Aura:USDC/DAI/[USDT]/USDC.e';
    }

    function setUp() public override { 
        primaryBorrowCurrency = USDT;
        super.setUp();

        minDeposit = 0.01e6;
        maxDeposit = 100_000e6;
    }
}
