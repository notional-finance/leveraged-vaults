// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Curve_USDe_xUSDC is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 19924489;
        harness = new Harness_SingleSidedLP_Curve_USDe_xUSDC();

        WHALE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 10_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Curve_USDe_xUSDC is 
Curve2TokenHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Curve:USDe/[USDC]';
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
        maxPrimaryBorrow = 2_000_000e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // USDe
        token[0] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        oracle[0] = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
        // USDC
        token[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[1] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](0);
        permissions = new ITradingModule.TokenPermissions[](0);

        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0xD6AA58cf21A0EDB33375D6c0434b8Bb5b589F021;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 3;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x04E80Db3f84873e4132B221831af1045D27f140F);

        
        _m.poolToken = IERC20(0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72);
        lpToken = 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](0);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Curve_USDe_xUSDC is Harness_SingleSidedLP_Curve_USDe_xUSDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Curve_USDe_xUSDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}