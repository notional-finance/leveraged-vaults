// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Aura_osETH_xWETH is VaultRewarderTests {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_osETH_xWETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e18;
        maxDeposit = 5e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Aura_osETH_xWETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Aura:osETH/[WETH]';
    }

    function getDeploymentConfig() public view override returns (
        VaultConfigParams memory params, uint80 maxPrimaryBorrow
    ) {
        params = getTestVaultConfig();
        params.feeRate5BPS = 15;
        params.liquidationRate = 103;
        params.reserveFeeShare = 80;
        params.maxBorrowMarketIndex = 2;
        params.minCollateralRatioBPS = 500;
        params.maxRequiredAccountCollateralRatioBPS = 10000;
        params.maxDeleverageCollateralRatioBPS = 800;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 0.1e8;
        maxPrimaryBorrow = 1e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // osETH
        token[0] = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
        oracle[0] = 0x3d3d7d124B0B80674730e0D31004790559209DEb;
        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](1);
        permissions = new ITradingModule.TokenPermissions[](1);

        // SWISE
        token[0] = 0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2;
        permissions[0] = ITradingModule.TokenPermissions(
            // 0x, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 8, tradeTypeFlags: 5 }
        );
        

        
    }

    constructor() {
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 1;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: 2000,
            oraclePriceDeviationLimitPercent: 0.015e4,
            numRewardTokens: 0,
            forceClaimAfter: 1 weeks
        });
        _m.rewardPool = IERC20(0x5F032f15B4e910252EDaDdB899f7201E89C8cD6b);

        

        _m.rewardTokens = new IERC20[](1);
        // SWISE
        _m.rewardTokens[0] = IERC20(0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Aura_osETH_xWETH is Harness_SingleSidedLP_Aura_osETH_xWETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Aura_osETH_xWETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}