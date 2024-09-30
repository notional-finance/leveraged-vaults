// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_tBTC_xWBTC is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 259043405;
        harness = new Harness_SingleSidedLP_Convex_tBTC_xWBTC();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.01e8;
        maxDeposit = 1e8;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_tBTC_xWBTC is 
Curve2TokenConvexHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:tBTC/[WBTC]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 20;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1300;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2300;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.05e8;
        maxPrimaryBorrow = 15e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // WBTC
        token[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        oracle[0] = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;
        // tBTC
        token[1] = 0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40;
        oracle[1] = 0xE808488e8627F6531bA79a13A9E0271B39abEb1C;
        
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
        EXISTING_DEPLOYMENT = 0x3533F05B2C54Ce1C2321cfe3c6F693A3cBbAEa10;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 4;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 5000,
            oraclePriceDeviationLimitPercent: 150,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0xa4Ed1e1Db18d65A36B3Ef179AaFB549b45a635A4);

        
        _m.poolToken = IERC20(0x186cF879186986A20aADFb7eAD50e3C20cb26CeC);
        lpToken = 0x186cF879186986A20aADFb7eAD50e3C20cb26CeC;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](1);
        // CRV
        _m.rewardTokens[0] = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_tBTC_xWBTC is Harness_SingleSidedLP_Convex_tBTC_xWBTC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_tBTC_xWBTC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}