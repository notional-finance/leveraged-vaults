// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Curve_xGHO_USDe is VaultRewarderTests {
    function setUp() public override {
        FORK_BLOCK = 19983100;
        harness = new Harness_SingleSidedLP_Curve_xGHO_USDe();

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

contract Harness_SingleSidedLP_Curve_xGHO_USDe is 
Curve2TokenHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Curve:[GHO]/USDe';
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
        // USDe
        token[1] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        oracle[1] = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](0);
        permissions = new ITradingModule.TokenPermissions[](0);

        

        
    }

    constructor() {
        EXISTING_DEPLOYMENT = 0xB1113cf888A019693b254da3d90f841072D85172;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 11;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2500,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 days
        });
        _m.rewardPool = IERC20(0x8eD00833BE7342608FaFDbF776a696afbFEaAe96);

        
        _m.poolToken = IERC20(0x670a72e6D22b0956C0D2573288F82DCc5d6E3a61);
        lpToken = 0x670a72e6D22b0956C0D2573288F82DCc5d6E3a61;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](0);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Curve_xGHO_USDe is Harness_SingleSidedLP_Curve_xGHO_USDe, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Curve_xGHO_USDe();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}