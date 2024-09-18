// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_xGHO_crvUSD is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 19983013;
        harness = new Harness_SingleSidedLP_Convex_xGHO_crvUSD();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e18;
        maxDeposit = 100e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        flashLender = 0x9E092cb431e5F1aa70e47e052773711d2Ba4917E;
        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_xGHO_crvUSD is 
Curve2TokenConvexHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:[GHO]/crvUSD';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 20;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1500;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 3300;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 60_000e8;
        maxPrimaryBorrow = 1_000_000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // GHO
        token[0] = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
        oracle[0] = 0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC;
        // crvUSD
        token[1] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        oracle[1] = 0xEEf0C605546958c1f899b6fB336C20671f9cD49F;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);

        // CRV
        token[0] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0x30fBa4a7ec8591f25B4D37fD79943a4bb6E553e2;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 11;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2500,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x5eC758f79b96AE74e7F1Ba9583009aFB3fc8eACB);

        
        _m.poolToken = IERC20(0x635EF0056A597D13863B73825CcA297236578595);
        lpToken = 0x635EF0056A597D13863B73825CcA297236578595;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](1);
        // CRV
        _m.rewardTokens[0] = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_xGHO_crvUSD is Harness_SingleSidedLP_Convex_xGHO_crvUSD, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_xGHO_crvUSD();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}