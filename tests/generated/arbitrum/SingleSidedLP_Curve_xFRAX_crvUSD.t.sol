// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Curve_xFRAX_crvUSD is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Curve_xFRAX_crvUSD();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.1e18;
        maxDeposit = 100_000e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Curve_xFRAX_crvUSD is 
Curve2TokenHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Curve:[FRAX]/crvUSD';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1000;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 1700;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 1e8;
        maxPrimaryBorrow = 100e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // FRAX
        token[0] = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
        oracle[0] = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;
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
        _m.primaryBorrowCurrency = 6;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100,
            numRewardTokens: 0,
            forceClaimAfter: 1 weeks
        });
        _m.rewardPool = IERC20(0x059E0db6BF882f5fe680dc5409C7adeB99753736);

        
        _m.poolToken = IERC20(0x2FE7AE43591E534C256A1594D326e5779E302Ff4);
        lpToken = 0x2FE7AE43591E534C256A1594D326e5779E302Ff4;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](2);
        // CRV
        _m.rewardTokens[0] = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        // ARB
        _m.rewardTokens[1] = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Curve_xFRAX_crvUSD is Harness_SingleSidedLP_Curve_xFRAX_crvUSD, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Curve_xFRAX_crvUSD();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}