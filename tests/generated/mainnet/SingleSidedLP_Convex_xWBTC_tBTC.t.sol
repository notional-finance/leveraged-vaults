// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_xWBTC_tBTC is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 20865202;
        harness = new Harness_SingleSidedLP_Convex_xWBTC_tBTC();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 0.01e8;
        maxDeposit = 1e8;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_xWBTC_tBTC is 
Curve2TokenConvexHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:[WBTC]/tBTC';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 10;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 0;
        params.minCollateralRatioBPS = 1300;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 2300;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 1e8;
        maxPrimaryBorrow = 50e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // WBTC
        token[0] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        oracle[0] = 0xa15652067333e979b314735b36AB7582071fa538;
        // tBTC
        token[1] = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
        oracle[1] = 0x8350b7De6a6a2C1368E7D4Bd968190e13E354297;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](0);
        permissions = new ITradingModule.TokenPermissions[](0);

        

        
    }
    function getRewardSettings() public pure override returns (StrategyVaultHarness.RewardSettings[] memory rewards) {
        rewards = new StrategyVaultHarness.RewardSettings[](2);
        // CRV
        rewards[0] = StrategyVaultHarness.RewardSettings({
            token: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            emissionRatePerYear: 0,
            endTime: 0
        });
        // CVX
        rewards[1] = StrategyVaultHarness.RewardSettings({
            token: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B,
            emissionRatePerYear: 0,
            endTime: 0
        });
        
    }

    function hasRewardReinvestmentRole() public view override returns (bool) {
        return false;
    }
    

    constructor() {
        EXISTING_DEPLOYMENT = 0xe20048FA0F165A49b780DFA9A8caBa845332f848;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 4;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 2,
            forceClaimAfter: 0
        });
        _m.rewardPool = IERC20(0x5793691B4ba69665213614d7ac722Db2d3f41927);

        
        _m.poolToken = IERC20(0xB7ECB2AA52AA64a717180E030241bC75Cd946726);
        lpToken = 0xB7ECB2AA52AA64a717180E030241bC75Cd946726;
        curveInterface = CurveInterface.V1;
        

        _m.rewardTokens = new IERC20[](2);
        // CRV
        _m.rewardTokens[0] = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
        // CVX
        _m.rewardTokens[1] = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_xWBTC_tBTC is Harness_SingleSidedLP_Convex_xWBTC_tBTC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_xWBTC_tBTC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}