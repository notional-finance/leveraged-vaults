// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_crvUSD_xUSDC is BaseSingleSidedLPVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_crvUSD_xUSDC();

        WHALE = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;
        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 90_000e6;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_crvUSD_xUSDC is 
Curve2TokenHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:crvUSD/[USDC]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 20;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 500;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 800;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 1e8;
        maxPrimaryBorrow = 5_000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDC
        token[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        oracle[0] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        // crvUSD
        token[1] = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;
        oracle[1] = 0x0a32255dd4BB6177C994bAAc73E0606fDD568f66;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        // CRV
        token[0] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        // ARB
        token[1] = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 3;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4
        });
        _m.rewardPool = IERC20(0xBFEE9F3E015adC754066424AEd535313dc764116);

        
        _m.poolToken = IERC20(0xec090cf6DD891D2d014beA6edAda6e05E025D93d);
        lpToken = 0xec090cf6DD891D2d014beA6edAda6e05E025D93d;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](2);
        // CRV
        _m.rewardTokens[0] = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        // ARB
        _m.rewardTokens[1] = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_crvUSD_xUSDC is Harness_SingleSidedLP_Convex_crvUSD_xUSDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_crvUSD_xUSDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}