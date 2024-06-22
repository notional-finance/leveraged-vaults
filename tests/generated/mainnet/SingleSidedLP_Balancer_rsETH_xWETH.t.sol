// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../SingleSidedLP/harness/index.sol";

contract Test_SingleSidedLP_Balancer_rsETH_xWETH is BaseSingleSidedLPVault {
    function setUp() public override {
        FORK_BLOCK = 20056700;
        harness = new Harness_SingleSidedLP_Balancer_rsETH_xWETH();

        // NOTE: need to enforce some minimum deposit here b/c of rounding issues
        // on the DEX side, even though we short circuit 0 deposits
        minDeposit = 1e18;
        maxDeposit = 100e18;
        maxRelEntryValuation = 50 * BASIS_POINT;
        maxRelExitValuation = 50 * BASIS_POINT;

        super.setUp();
    }
}

contract Harness_SingleSidedLP_Balancer_rsETH_xWETH is 
ComposablePoolHarness
 {
    function getVaultName() public pure override returns (string memory) {
        return 'SingleSidedLP:Balancer:rsETH/[WETH]';
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
        params.maxDeleverageCollateralRatioBPS = 2700;

        // NOTE: these are always in 8 decimals
        params.minAccountBorrowSize = 30e8;
        maxPrimaryBorrow = 250e8;
    }

    function getRequiredOracles() public override pure returns (
        address[] memory token, address[] memory oracle
    ) {
        token = new address[](2);
        oracle = new address[](2);

        // rsETH
        token[0] = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
        oracle[0] = 0x150aab1C3D63a1eD0560B95F23d7905CE6544cCB;
        // ETH
        token[1] = 0x0000000000000000000000000000000000000000;
        oracle[1] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        
    }

    function getTradingPermissions() public pure override returns (
        address[] memory token, ITradingModule.TokenPermissions[] memory permissions
    ) {
        token = new address[](0);
        permissions = new ITradingModule.TokenPermissions[](0);

        

        
    }

    constructor() {
        balancerPoolId = 0x58aadfb1afac0ad7fca1148f3cde6aedf5236b6d00000000000000000000067f;
        balancerPool = 0x58AAdFB1Afac0ad7fca1148f3cdE6aEDF5236B6D;
        SingleSidedLPMetadata memory _m;
        _m.primaryBorrowCurrency = 1;
        _m.settings = StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            deprecated_poolSlippageLimitPercent: 0,
            maxPoolShare: 3000,
            oraclePriceDeviationLimitPercent: 0.015e4
        });
        _m.rewardPool = IERC20(0x0000000000000000000000000000000000000000);

        

        _m.rewardTokens = new IERC20[](0);
        
        setMetadata(_m);
    }
}

contract Deploy_SingleSidedLP_Balancer_rsETH_xWETH is Harness_SingleSidedLP_Balancer_rsETH_xWETH, DeployProxyVault {
    function setUp() public override {
        harness = new Harness_SingleSidedLP_Balancer_rsETH_xWETH();
    }

    function deployVault() internal override returns (address impl, bytes memory _metadata) {
        return deployVaultImplementation();
    }
}