// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_xFRAX_USDC_e is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 249745375;
        harness = new Harness_SingleSidedLP_Convex_xFRAX_USDC_e();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 10_000e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_xFRAX_USDC_e is 
Curve2TokenConvexHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:[FRAX]/USDC.e';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 900;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 1500;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 1_000e8;
        maxPrimaryBorrow = 200_000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // FRAX
        token[0] = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
        oracle[0] = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;
        // USDC_e
        token[1] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        oracle[1] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);

        // CRV
        token[0] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0xdb08f663e5D765949054785F2eD1b2aa1e9C22Cf;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 6;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x93729702Bf9E1687Ae2124e191B8fFbcC0C8A0B0);

        
        _m.poolToken = IERC20(0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5);
        lpToken = 0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5;
        curveInterface = CurveInterface.V1;
        

        _m.rewardTokens = new IERC20[](1);
        // CRV
        _m.rewardTokens[0] = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_xFRAX_USDC_e is Harness_SingleSidedLP_Convex_xFRAX_USDC_e, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_xFRAX_USDC_e();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}