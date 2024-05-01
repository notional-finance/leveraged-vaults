// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Convex_pyUSD_xUSDC is VaultRewarderTests {
    function _stringEqual(string memory a, string memory b) private pure returns(bool) {
      return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _shouldSkip(string memory name) internal pure override returns(bool) {
        if (_stringEqual(name, "test_claimReward_WithChangingForceClaimAfter")) return true;
        
        return false;
    }

    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_pyUSD_xUSDC();

        WHALE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e6;
        maxDeposit = 50_000e6;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 75 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Convex_pyUSD_xUSDC is 
Curve2TokenHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Convex:pyUSD/[USDC]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 20;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 1100;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 1900;

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
        token[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        oracle[0] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        // pyUSD
        token[1] = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
        oracle[1] = 0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](3);
        permissions = new ITradingModule.TokenPermissions[](3);

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
        // pyUSD
        token[2] = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
        permissions[2] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0x84e58d8faA4e3B74d55D9fc762230f15d95570B8;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 3;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 weeks
        });
        _m.rewardPool = IERC20(0xc583e81bB36A1F620A804D8AF642B63b0ceEb5c0);
        _m.whitelistedReward = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
        

        
        _m.poolToken = IERC20(0x383E6b4437b59fff47B619CBA855CA29342A8559);
        lpToken = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](3);
        // CRV
        _m.rewardTokens[0] = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
        // CVX
        _m.rewardTokens[1] = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
        // pyUSD
        _m.rewardTokens[2] = IERC20(0x6c3ea9036406852006290770BEdFcAbA0e23A0e8);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Convex_pyUSD_xUSDC is Harness_SingleSidedLP_Convex_pyUSD_xUSDC, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Convex_pyUSD_xUSDC();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}