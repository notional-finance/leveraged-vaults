// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_xUSDT_crvUSD is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_xUSDT_crvUSD();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 10_000e6;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        flashLender = 0x9E092cb431e5F1aa70e47e052773711d2Ba4917E;
        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_xUSDT_crvUSD is 
Curve2TokenConvexHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:[USDT]/crvUSD';
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
        params.minAccountBorrowSize = 100_000e8;
        maxPrimaryBorrow = 5_000_000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDT
        token[0] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        oracle[0] = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
        // crvUSD
        token[1] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        oracle[1] = 0xEEf0C605546958c1f899b6fB336C20671f9cD49F;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        // CRV
        token[0] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        // CVX
        token[1] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0x86B222d44AC6cC56e75b3df01fdAD5Dc371EF538;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 8;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0xD1DdB0a0815fD28932fBb194C84003683AF8a824);

        
        _m.poolToken = IERC20(0x390f3595bCa2Df7d23783dFd126427CCeb997BF4);
        lpToken = 0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
        curveInterface = CurveInterface.V1;
        

        _m.rewardTokens = new IERC20[](2);
        // CRV
        _m.rewardTokens[0] = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
        // CVX
        _m.rewardTokens[1] = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_xUSDT_crvUSD is Harness_SingleSidedLP_Convex_xUSDT_crvUSD, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_xUSDT_crvUSD();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}