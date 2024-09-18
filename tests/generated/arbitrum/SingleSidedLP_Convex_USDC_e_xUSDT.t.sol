// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_USDC_e_xUSDT is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 242772900;
        harness = new Harness_SingleSidedLP_Convex_USDC_e_xUSDT();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 100_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_USDC_e_xUSDT is 
Curve2TokenConvexHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:USDC.e/[USDT]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 102;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1300;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 1900;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.001e8;
        maxPrimaryBorrow = 100e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDT
        token[0] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        oracle[0] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
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
        EXISTING_DEPLOYMENT = 0x431dbfE3050eA39abBfF3E0d86109FB5BafA28fD;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 8;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 100,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x971E732B5c91A59AEa8aa5B0c763E6d648362CF8);

        
        _m.poolToken = IERC20(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
        lpToken = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
        curveInterface = CurveInterface.V1;
        

        _m.rewardTokens = new IERC20[](1);
        // CRV
        _m.rewardTokens[0] = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_USDC_e_xUSDT is Harness_SingleSidedLP_Convex_USDC_e_xUSDT, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_USDC_e_xUSDT();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}