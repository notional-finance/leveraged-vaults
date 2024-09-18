// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_crvUSD_xUSDT is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_crvUSD_xUSDT();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 10_000e6;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_crvUSD_xUSDT is 
Curve2TokenConvexHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:crvUSD/[USDT]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 20;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1400;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2600;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 5_000e8;
        maxPrimaryBorrow = 500_000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDT
        token[0] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        oracle[0] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
        // crvUSD
        token[1] = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;
        oracle[1] = 0x0a32255dd4BB6177C994bAAc73E0606fDD568f66;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);

        // ARB
        token[0] = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0xae04e4887cBf5f25c05aC1384BcD0b7e885a1F4A;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 8;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0xf74d4C9b0F49fb70D8Ff6706ddF39e3a16D61E67);

        
        _m.poolToken = IERC20(0x73aF1150F265419Ef8a5DB41908B700C32D49135);
        lpToken = 0x73aF1150F265419Ef8a5DB41908B700C32D49135;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](1);
        // ARB
        _m.rewardTokens[0] = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_crvUSD_xUSDT is Harness_SingleSidedLP_Convex_crvUSD_xUSDT, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_crvUSD_xUSDT();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}