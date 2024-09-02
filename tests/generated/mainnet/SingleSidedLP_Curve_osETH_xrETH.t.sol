// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Curve_osETH_xrETH is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Curve_osETH_xrETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e18;
        maxDeposit = 100e18;
        maxRelEntryValuation = 75 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Curve_osETH_xrETH is 
Curve2TokenHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Curve:osETH/[rETH]';
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

        // osETH
        token[0] = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
        oracle[0] = 0x3d3d7d124B0B80674730e0D31004790559209DEb;
        // rETH
        token[1] = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        oracle[1] = 0xA7D273951861CF07Df8B0A1C3c934FD41bA9E8Eb;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](2);
        permissions = new ITradingModule.TokenPermissions[](2);

        // RPL
        token[0] = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        // SWISE
        token[1] = 0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2;
        permissions[1] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 7;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 weeks
        });
        _m.rewardPool = IERC20(0x63037a4e3305d25D48BAED2022b8462b2807351c);

        
        _m.poolToken = IERC20(0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d);
        lpToken = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
        curveInterface = CurveInterface.StableSwapNG;
        

        _m.rewardTokens = new IERC20[](2);
        // RPL
        _m.rewardTokens[0] = IERC20(0xD33526068D116cE69F19A9ee46F0bd304F21A51f);
        // SWISE
        _m.rewardTokens[1] = IERC20(0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Curve_osETH_xrETH is Harness_SingleSidedLP_Curve_osETH_xrETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Curve_osETH_xrETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}